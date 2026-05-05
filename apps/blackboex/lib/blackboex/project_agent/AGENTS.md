# Project Agent Context

The orchestration core that decomposes a user's natural-language project
request into a typed multi-step `Plan` and dispatches each `PlanTask` to
the matching per-artifact agent (`Agent`, `FlowAgent`, `PageAgent`,
`PlaygroundAgent`). Composes; never generates code itself.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.ProjectAgent` | Public facade. `start_planning/3` opens a `ProjectConversation`+`ProjectRun` and enqueues `KickoffWorker`. `approve_and_run/3` approves a draft plan and enqueues `PlanRunnerWorker`. External callers use ONLY this. |
| `Blackboex.ProjectAgent.Planner` | Pure module. Builds the prompt (stable + volatile via `LLM.PromptCache`), drives typed emission via `ReqLLM.Generation.generate_object/4` (or a test-stubbed `:project_planner_client` fun), returns `{:ok, %{plan_attrs, task_attrs}}`. Calls `Budget.touch_run/1` for heartbeat. Tier `:planner`. |
| `Blackboex.ProjectAgent.ProjectIndex` | Lightweight metadata-only index (`apis`, `flows`, `pages`, `playgrounds` per project). ETS-cached by `(project_id, max_artifact_updated_at)` so any artifact mutation auto-invalidates. The cache key is also embedded in the rendered text so prompt-cache hits are content-addressed. |
| `Blackboex.ProjectAgent.KickoffWorker` | Oban worker on `:project_orchestration` (`max_attempts: 3`). Opens a `ProjectConversation`+`ProjectRun`, calls `Planner.build_plan/2`, persists `Plan` + `PlanTask` rows in `:draft`, broadcasts `{:plan_drafted, %{id, project_id, plan}}` on `project_plan:#{plan.id}` AND `project_plan:project:#{project.id}`. |
| `Blackboex.ProjectAgent.PlanRunnerWorker` | Oban worker on `:project_orchestration` (`max_attempts: 3`). Finds the next `:pending` task, generates a `child_run_id`, marks the task `:running` with that id, `Oban.insert!`s the matching child `KickoffWorker.new(%{run_id: child_run_id, …})`, calls `Budget.touch_run/1`, exits. Re-enqueued by `RecoveryWorker` after each terminal pickup. Finalizes the plan when all tasks are terminal (halt-on-fail per D6). |
| `Blackboex.ProjectAgent.BroadcastAdapter` | Bridges per-artifact terminal events into the uniform LiveView-facing message `{:project_task_completed, %{plan_id, task_id, status, error}}` on `project_plan:#{plan.id}`. `handle_terminal/4` is the production entry point (called by `RecoveryWorker`). **Idempotent.** `translate_message/2` and `topic_for/1` are vestigial (designed for option (c) listener that v1 does not ship); kept for backward-compatible tests but unused by the production caller. |
| `Blackboex.ProjectAgent.RecoveryWorker` | Oban cron worker (registered every minute via `Oban.Plugins.Cron` in `config/config.exs`). Polls `Plans.list_running_tasks/0`; for each `:running` task with non-nil `child_run_id`, fetches the matching child Run via the appropriate `*Conversations.get_run/1` (`api`/`flow`/`page`/`playground`) and calls `BroadcastAdapter.handle_terminal/4` when terminal or stale. **This is the production caller of `handle_terminal/4`.** |

## Public API (`Blackboex.ProjectAgent`)

```elixir
@spec start_planning(Project.t(), User.t(), String.t()) ::
        {:ok, ProjectConversation.t(), ProjectRun.t()} | {:error, term()}

@spec approve_and_run(Plan.t(), User.t(), %{markdown_body: String.t()}) ::
        {:ok, Plan.t()} | {:error, term()}
```

## Listener pattern (decision)

Production runs **option (b) — Poll-only via `RecoveryWorker` cron**.

`PlanRunnerWorker.perform/1` exits cleanly between dispatches; the per-task `BroadcastAdapter.subscribe/2` call would die with the worker process and never receive the child terminal. Instead, `RecoveryWorker` runs every minute (Oban cron `* * * * *` configured in `config/config.exs`), queries `Plans.list_running_tasks/0`, fetches the matching child Run row by `child_run_id`, and drives `BroadcastAdapter.handle_terminal/4` when the child is terminal or stale (>15 min since last update).

Why (b) over (c) for v1:

- Listener-process management for option (c) (DynamicSupervisor + Registry + per-task GenServer state machine) is justified only by sub-second happy-path latency. Plans run on the order of minutes; saving a poll cycle is not the bottleneck.
- The poll-based design is restart-safe by construction: a node crash leaves `:running` tasks in the DB, and the next cron tick picks them up.
- `handle_terminal/4` is idempotent, so multiple cron ticks for the same terminal task are safe.

If option (c) ever lands later, it replaces the `RecoveryWorker` cron pickup, not augments it. The `BroadcastAdapter.handle_terminal/4` contract is the seam.

## Broadcast contract

| Inbound surface (per-artifact) | Topic | Native terminal tuple |
|---|---|---|
| `Agent` (api) | `run:#{run_id}` | `{:agent_completed, %{run_id, status, ...}}` / `{:agent_failed, %{run_id, error}}` |
| `FlowAgent` | `flow_agent:flow:#{flow_id}` | `{:run_completed, %{run_id, ...}}` / `{:run_failed, %{run_id, reason}}` |
| `PageAgent` | `page_agent:#{org_id}:page:#{page_id}` | `{:run_completed, %{run_id, ...}}` / `{:run_failed, %{run_id, reason}}` |
| `PlaygroundAgent` | `playground_agent:run:#{run_id}` | `{:run_completed, %{run_id, ...}}` / `{:run_failed, %{run_id, reason}}` |

| Outbound surface (uniform) | Topic | Tuple |
|---|---|---|
| LiveView per-plan | `project_plan:#{plan.id}` | `{:plan_drafted, %{id, project_id, plan}}` after kickoff |
| LiveView per-plan | `project_plan:#{plan.id}` | `{:project_task_completed, %{plan_id, task_id, status, error}}` after each child terminal |
| LiveView project-scoped | `project_plan:project:#{project_id}` | `{:plan_drafted, %{id, project_id, plan}}` (used before any plan id exists) |

`status` ∈ `:completed | :failed`. `error` is `nil` on success or the surface's reason payload (`error`/`reason`) on failure.

## Heartbeat protocol

The `Budget.touch_run/1` (`apps/blackboex/lib/blackboex/agent/pipeline/budget.ex:236`) is the existing project-wide heartbeat — used 14+ times in `agent/pipeline/generation.ex` and `validation.ex`. The Project Agent calls it:

1. In `Planner.build_plan/2` — once before the LLM call, once after, so the planner Run does not appear stale during slow object emission.
2. In `PlanRunnerWorker.dispatch_next/2` — once per task dispatch so the planner Run stays fresh while a child runs.

Without these touches, `Agent.RecoveryWorker` (cron `*/2 * * * *`) would mark the planner Run failed at the 120s stale threshold even though work is in flight.

## Cache discipline

Every Project Agent prompt-cache segment goes through `Blackboex.LLM.PromptCache.stable_segment/2` (the sole sanctioned constructor). The Credo check `Credo.Check.Custom.AnthropicCacheTtl` enforces:

1. No bare `cache_control:` literal outside `lib/blackboex/llm/prompt_cache.ex` and `lib/blackboex/project_agent/`.
2. Inside the sanctioned scope, every `cache_control:` map must include `ttl:` with a literal binary (`"5m"` or `"1h"`).

The Planner uses `ttl: "1h"` for the stable prefix (system + tools + ProjectIndex digest). The volatile suffix uses `volatile_segment/1` (no `cache_control`).

## Tier routing

All Project Agent LLM calls flow through `Blackboex.LLM.Config.client_for_project(project_id, tier: :planner)`. The matching per-tier rate-limit cap comes from `Blackboex.LLM.RateLimiter.check_rate(user_id, plan, tier: :planner)`. `LLM.record_usage/1` is called with `:tier => :planner` so per-tier telemetry (M7) sees the planner spend.

## Continuation mode (M7)

`KickoffWorker.perform/1` recognizes a continuation-mode args map
(`%{"continuation" => true, "parent_plan_id" => …, "plan_id" => …}`).
The LiveView enqueues this AFTER `Plans.start_continuation/2` has
already created the draft Plan with parent's `:done` tasks copied as
`:skipped`. The worker:

1. Loads the parent and the existing draft Plan (must be `:draft`).
2. Builds a `prior_partial_summary` string (parent status, failure
   reason, completed/failed/pending titles).
3. Calls `Planner.build_plan/2` with `:prior_partial_summary` so the LLM
   sees the failure context in the volatile prompt segment.
4. Appends the produced `:pending` tasks via
   `Plans.add_planner_tasks_to_continuation/2`.
5. Re-broadcasts `:plan_drafted` on `project_plan:#{plan.id}` and
   `project_plan:project:#{project.id}` so the LV picks up the now-full
   draft unchanged.

The continuation-mode worker does NOT create a new ProjectConversation/
ProjectRun — the parent's run remains the conversation anchor for the
plan family.

## Phase 2 follow-ups (out of v1 scope — confirmed deferred)

- **Listener pattern (c): per-task GenServer broadcast listener** with DynamicSupervisor + Registry. v1 uses option (b) `RecoveryWorker` poll-based pickup; option (c) would replace it for sub-second latency. `handle_terminal/4` is the seam — switching listener strategy doesn't change other modules.
- **Property-Based Testing in `TestGenerator`** (+12pp bug detection per arXiv 2506.18315/2510.25297). Pertinent to per-artifact agents, not ProjectAgent itself.
- **Event digest in Planner prompt** for very long plans (current ProjectIndex digest is metadata-only, sufficient for v1).
- **Oban Pro Workflows DAG** for `PlanRunnerWorker` — replaces sequential dispatch when parallel independent tasks become valuable (requires Oban Pro license).
- **Cascade model retry inside the per-artifact executor** — start cheap, escalate to Opus on compile/lint/test failure.
- **Vector-based `ProjectIndex` (RAG)** — only when metadata-only listings stop fitting the planner context.
- **Workspace-level cache isolation empirical test** — verify project_id namespace doesn't leak prefix between tenants once provider tooling exists.
- **Drop the vestigial `BroadcastAdapter.subscribe/2` and `topic_for/1`** when option (c) is either chosen or formally rejected. They're currently kept for backward-compatible tests; production callers do not use them.
- **`do_call_req_llm/2` real-Session happy-path test**: M8's `project_agent_real_session_test.exs` exercises the failure path end-to-end (the per-artifact Run reaches `:failed` and `RecoveryWorker` picks it up). A green-path test that drives a deterministic compile+lint+test pipeline through `Agent.Session` is non-trivial fixture work; deferred until the per-artifact agents stabilize their public seams.

## v1 status (audited 2026-05-05)

All M1–M8 milestones landed plus a post-audit gap-fix pass that closed the 5 critical gaps surfaced by `.omc/audit/{critic,verifier}-audit.md`:

- **Planner LLM call** (`planner.ex`) — calls `ReqLLM.Generation.generate_object/4` for real with the project's per-tier client. Falls back to `{:error, :planner_backend_not_configured}` only when `LLMConfig.client_for_project(project_id, tier: :planner)` returns `:not_configured` (no Anthropic key set on the project). The `:project_planner_client` config seam exists for tests/dev; production path is the real call.
- **PlanRunnerWorker dispatch** (`plan_runner_worker.ex`) — `enqueue_child/2` generates a real `child_run_id` and `Oban.insert!`s the matching per-artifact KickoffWorker (`Agent`, `FlowAgent`, `PageAgent`, `PlaygroundAgent`). The 4 per-artifact KickoffWorkers all accept an optional `run_id` arg and adopt it as the pre-supplied row id (verified at `agent/kickoff_worker.ex:39`, `flow_agent/kickoff_worker.ex:39`, `page_agent/kickoff_worker.ex:41`, `playground_agent/kickoff_worker.ex:38`).
- **RecoveryWorker production caller** (`recovery_worker.ex`) — registered via Oban cron `* * * * *` in `config/config.exs`. Polls `:running` tasks, fetches matching child Run by `child_run_id`, calls `BroadcastAdapter.handle_terminal/4` for terminal or stale runs. Stale-detection handles both `DateTime` and `NaiveDateTime` `updated_at` fields.
- **Tier routing wired** — `KickoffWorker.perform/1` calls `RateLimiter.check_rate(user.id, org.plan, tier: :planner)` before invoking the Planner. Planner uses `LLMConfig.client_for_project(project_id, tier: :planner)` and emits `LLM.record_usage` with `tier: :planner` for telemetry.
- **Real-Session integration test rewritten** — `apps/blackboex/test/integration/project_agent_real_session_test.exs` now drives the production wiring end-to-end: `ProjectAgent.start_planning` → `KickoffWorker` (with `:project_planner_client` stub) → `Plans.create_draft_plan` → `approve_and_run` → `PlanRunnerWorker` (real `Oban.insert!` of `Agent.KickoffWorker` asserted via `assert_enqueued`) → DB-side terminal-state simulation → `RecoveryWorker.perform/1` (production caller) → uniform `{:project_task_completed, …}` broadcast asserted. The test does NOT call `handle_terminal/4` directly.

Known production limitation: a project must have an Anthropic API key configured in `ProjectEnvVars` for the planner to function. Without it, `client_for_project` returns `:not_configured` and `KickoffWorker` records the run as failed. The LiveView surfaces this via the standard error-flash path (no special-case UX).
