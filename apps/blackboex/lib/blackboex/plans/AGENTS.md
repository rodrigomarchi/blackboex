# Plans Context

Project-level multi-step plans produced by the Project Agent. Plans are
typed (`Plan` + `PlanTask` Ecto schemas), rendered to markdown for the
draft editor, and re-validated against their schemas on approval before
any work runs. After `:approved`, plans are immutable — re-plan creates
a new `Plan` with `parent_plan_id` pointing at its predecessor (gate D2,
fresh approval required).

## Modules

| Module | Role |
|--------|------|
| `Blackboex.Plans` | Public facade. `defdelegate` to `Plans.Plans`. External callers (web, workers) use ONLY this. |
| `Blackboex.Plans.Plans` | Sub-context. State machine, transitions, concurrent-approve race translation, `start_continuation/2`, plan/task creation. |
| `Blackboex.Plans.PlanQueries` | Pure `Ecto.Query` builders (`for_project/2`, `active_for_project/1`, `tasks_for_plan/1`, `done_tasks_for_plan/1`, `task_by_child_run_id/1`). NO `Repo.*` calls inside. |
| `Blackboex.Plans.MarkdownRenderer` | `render/1 :: Plan.t() -> String.t()`. Pure. Renders header (title, project id, optional prior failure) plus a numbered `## N. {title}` block per task with `- artifact_type:`, `- action:`, `- target_artifact_id:`, `- params:`, `- acceptance_criteria:` bullets. |
| `Blackboex.Plans.MarkdownParser` | `parse_and_validate/2 :: (String.t(), Plan.t()) -> {:ok, %{title, tasks}} \| {:error, [violation()]}`. Re-parses (possibly user-edited) markdown and validates that edits respect plan invariants. |
| `Blackboex.Plans.Plan` | Schema. Statuses: `"draft" \| "approved" \| "running" \| "done" \| "partial" \| "failed"`. UNIQUE-partial index `plans_one_active_per_project_idx` enforces one active plan per project. |
| `Blackboex.Plans.PlanTask` | Schema. Statuses: `"pending" \| "running" \| "done" \| "failed" \| "skipped"`. `:skipped` is creation-time-only (validated in changeset). |

## Public API (every function `@spec`-annotated)

```elixir
@type violation :: {:invalid_artifact_type, integer()} | {:invalid_action, integer()}
                | {:order_changed, integer()} | {:target_artifact_changed, integer()}
                | {:structural_field_renamed, atom()}
@type plan_error :: :concurrent_active_plan | :already_terminal | :parent_still_active
                  | :invalid_markdown_edit | {:invalid_markdown_edit, [violation]}
                  | Ecto.Changeset.t()

@spec list_plans_for_project(Ecto.UUID.t(), keyword()) :: [Plan.t()]
@spec get_plan!(Ecto.UUID.t()) :: Plan.t()
@spec get_active_plan(Ecto.UUID.t()) :: Plan.t() | nil
@spec list_tasks(Plan.t()) :: [PlanTask.t()]
@spec get_task!(Ecto.UUID.t()) :: PlanTask.t()

@spec create_draft_plan(Project.t(), User.t(), %{user_message, tasks, title, markdown_body}) ::
        {:ok, Plan.t()} | {:error, plan_error()}
@spec approve_plan(Plan.t(), User.t(), %{markdown_body}) ::
        {:ok, Plan.t()} | {:error, plan_error()}
@spec mark_plan_running(Plan.t()) :: {:ok, Plan.t()} | {:error, plan_error()}
@spec mark_plan_done(Plan.t())    :: {:ok, Plan.t()} | {:error, plan_error()}
@spec mark_plan_partial(Plan.t(), String.t()) :: {:ok, Plan.t()} | {:error, plan_error()}
@spec mark_plan_failed(Plan.t(),  String.t()) :: {:ok, Plan.t()} | {:error, plan_error()}
@spec start_continuation(Plan.t(), User.t()) :: {:ok, Plan.t()} | {:error, plan_error()}
@spec add_planner_tasks_to_continuation(Plan.t(), [map()]) ::
        {:ok, Plan.t()} | {:error, :not_draft | Ecto.Changeset.t()}

@spec mark_task_running(PlanTask.t(), child_run_id :: Ecto.UUID.t()) ::
        {:ok, PlanTask.t()} | {:error, Ecto.Changeset.t()}
@spec mark_task_done(PlanTask.t())   :: {:ok, PlanTask.t()} | {:error, Ecto.Changeset.t()}
@spec mark_task_failed(PlanTask.t(), String.t()) :: {:ok, PlanTask.t()} | {:error, Ecto.Changeset.t()}
# NO mark_task_skipped — `:skipped` is creation-time-only.
```

## State Machine

```
                      ┌──────────────────────────────────────────┐
                      │            create_draft_plan             │
                      ▼                                          │
                   :draft                                        │
                      │                                          │
                      │ approve_plan                             │
                      │ (parses + revalidates markdown)          │
                      ▼                                          │
                  :approved ─── mark_plan_failed ─────────► :failed
                      │
                      │ mark_plan_running
                      ▼
                  :running ─── mark_plan_done ───────────► :done
                      │
                      ├── mark_plan_partial(reason) ─────► :partial
                      │
                      └── mark_plan_failed(reason)  ─────► :failed

   any terminal state + any transition → {:error, :already_terminal}
```

Re-plan from a `:partial` or `:failed` parent:

```
parent.status == :partial OR :failed
        │
        │ start_continuation(parent, user)
        ▼
new draft Plan with parent_plan_id = parent.id
  + parent.tasks where status == :done copied as :skipped on new plan
  (creation-time-only — PlanTask changeset rejects later transitions to :skipped)

→ requires fresh approve_plan call (gate D2)
```

After `start_continuation/2` produces the draft (with parent's `:done` tasks copied as `:skipped`), the LiveView enqueues `ProjectAgent.KickoffWorker` in continuation mode (`continuation: true, parent_plan_id, plan_id`). The worker calls `Planner.build_plan/2` with `:prior_partial_summary` (built from the parent's failure context + task statuses) and appends the produced `:pending` tasks via `Plans.add_planner_tasks_to_continuation/2`. The Plan never re-creates its conversation/run from scratch and `Plans` stays independent of `Planner` (which lives in `ProjectAgent`).

## Concurrency invariant

Partial UNIQUE index `plans_one_active_per_project_idx ON plans (project_id) WHERE status IN ('approved','running')` enforces "at most one active plan per project". `Plans.approve_plan/3` translates the constraint violation into `{:error, :concurrent_active_plan}` for the loser. Two layers of translation:

1. **Update path (common case).** Ecto's `unique_constraint(:project_id, ...)` on `Plan.status_changeset/2` turns the violation into a changeset error with `[constraint: :unique, constraint_name: "plans_one_active_per_project_idx"]`. The facade detects this and returns the structured tuple.
2. **Insert path (defensive).** A `try/rescue Ecto.ConstraintError` wraps the entire approval transaction so that a violation thrown from a path Ecto did not declare a unique_constraint for still maps to `{:error, :concurrent_active_plan}`.

`:draft` plans are excluded from the active filter, so re-plan via `start_continuation/2` never collides with the parent's slot.

True parallelism (multiple OS processes hitting Postgres simultaneously) cannot be observed inside the Ecto SQL sandbox — every test transaction shares the outer test transaction. The semantically equivalent test sequences two approvals against the same project; the second carries a stale `:draft` snapshot, the partial-unique index fires at UPDATE time, the wrapper produces the structured tuple. See `test/blackboex/plans/concurrent_approval_test.exs`.

## Markdown render/parse contract

Format (MarkdownRenderer emits exactly this; MarkdownParser parses exactly this):

```
# {plan.title}

_Project ID: {plan.project_id}_

> Prior failure: {plan.failure_reason}    # only if non-nil

## 1. {task.title}
- artifact_type: api|flow|page|playground
- action: create|edit
- target_artifact_id: {uuid or "nil"}
- params: %{...}
- acceptance_criteria:
  - bullet 1
  - bullet 2
```

Allowed edits (round-trip clean):

- `acceptance_criteria` text (any number of bullets)
- `params` map content (within structural keys)
- task `title`
- Reordering tasks. v1 keeps `:order_changed` violation type for future use but does NOT emit it (dependencies aren't first-class yet).

Forbidden edits (each surfaces a `violation/0`):

- `:invalid_artifact_type` — `artifact_type` outside `~w(api flow page playground)`
- `:invalid_action` — `action` outside `~w(create edit)`
- `:target_artifact_changed` — changing `target_artifact_id` for an `edit` task
- `:structural_field_renamed` — renaming any of `:artifact_type`, `:action`, `:target_artifact_id`, `:params`, `:acceptance_criteria`, or omitting the `# title` heading

`approve_plan/3` calls `parse_and_validate/2`; on `:error` returns `{:error, {:invalid_markdown_edit, violations}}`.

## SPIKE outcome (typed plan emission backend)

**Decision: PASS — M5 commits to `ReqLLM.Generation.generate_object/4`.**

The M2 spike (`test/blackboex/plans/typed_emission_spike_test.exs`, `@moduletag :integration`) verifies:

1. **Exported / arity-4.** `Code.ensure_loaded?(ReqLLM.Generation)` and `function_exported?(ReqLLM.Generation, :generate_object, 4)` both pass against the installed `req_llm` version (deps tree confirms `ReqLLM.Generation.generate_object/4` is defined and used internally).
2. **Object validates against an Ecto changeset.** Casting a well-shaped string-keyed or atom-keyed map to a stripped-down `PlanTask`-shaped embedded schema produces a valid changeset that survives `Ecto.Changeset.apply_action/2`.
3. **Failure modes surface as `{:error, _}`.** Schema mismatches (invalid enum value, missing required field, extra unknown garbage) yield invalid changesets — the test's wrapper turns those into `{:error, {:invalid_object, %Ecto.Changeset{}}}` without raising.

Fallback (NOT exercised in M2): if a future `req_llm` upgrade removes or renames `generate_object/4`, M5's Planner should switch to `instructor_lite ~> 1.2` (already declared in `apps/blackboex/mix.exs`). Wrap `InstructorLite.instruct/2` with the existing `LLM.allow?/2` + `LLM.CircuitBreaker` checks so rate-limit / circuit-breaker invariants are not bypassed.

The spike test runs as part of `make test` (no `:slow` tag; `@moduletag :integration` is not excluded by the default suite).

## Database

| Table | Key columns |
|-------|-------------|
| `plans` | partial UNIQUE `(project_id) WHERE status IN ('approved','running')` (`plans_one_active_per_project_idx`); indexes on `(project_id, status)`, `(run_id)`, `(parent_plan_id)`, `(approved_by_user_id)`. FKs: `project_id` cascade, `run_id` nilify, `parent_plan_id` nilify, `approved_by_user_id` nilify. |
| `plan_tasks` | unique `(plan_id, order)`; indexes on `(plan_id, status)`, `(child_run_id)`. FK: `plan_id` cascade. |

## Fixtures

`Blackboex.PlansFixtures` is auto-imported via `DataCase` and `ConnCase`:
- `plan_fixture(attrs)` — default `status: "draft"`. Pass `:project` (auto-created if not).
- `plan_task_fixture(attrs)` — default `artifact_type: "api"`, `action: "create"`, `status: "pending"`, auto-incremented `order` per plan.
- `approved_plan_fixture(attrs)` — Plan in `:approved` state with one task.
- `partial_plan_fixture(attrs)` — Plan in `:partial` state with one `:done` task at `order: 0` and one `:failed` task at `order: 1`. Canonical "needs continuation" shape.
- Named setups: `:create_plan`, `:create_plan_task`, `:create_partial_plan`.

## Out of scope (M3+ milestones)

- Project-level Planner LLM call assembling the prompt (M5)
- `PlanRunnerWorker` callback-driven advancement (M5)
- LLM tier routing (`:planner`/`:executor`/`:navigation`) and `tier` plumbing on `LLM.Usage` (M4)
- Custom Credo check `Credo.Check.Custom.AnthropicCacheTtl` (M4)
- LiveView UI / `Blackboex.Features` flag (M6)
- Per-tier telemetry (`:llm_tokens_by_tier`) (M7)
