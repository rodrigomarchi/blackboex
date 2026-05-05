# AGENTS.md — Domain App (blackboex)

Pure business logic. Zero Phoenix dependencies. All contexts accessed via facade modules.

Each context has its own AGENTS.md — **read it before generating code in that area.**

## Context Map

| Context | Facade | Key Schemas | Query Module |
|---------|--------|-------------|--------------|
| **Accounts** | `Blackboex.Accounts` | User, UserToken, Scope | `UserQueries` |
| **Organizations** | `Blackboex.Organizations` | Organization, Membership, Invitation | `OrganizationQueries` |
| **Settings** | `Blackboex.Settings` | InstanceSetting | — |
| **Onboarding** | `Blackboex.Onboarding` | — | — |
| **Apis** | `Blackboex.Apis` | Api, ApiKey, ApiVersion, ApiFile | `ApiQueries`, `FileQueries`, `VersionQueries` |
| **Flows** | `Blackboex.Flows` | Flow | `FlowQueries` |
| **FlowExecutions** | `Blackboex.FlowExecutions` | FlowExecution, NodeExecution | `FlowExecutionQueries` |
| **ProjectEnvVars** | `Blackboex.ProjectEnvVars` | ProjectEnvVar | `ProjectEnvVarQueries` |
| **Projects** | `Blackboex.Projects` | Project, ProjectMembership | `ProjectQueries` |
| **Samples** | `Blackboex.Samples.Manifest` | — | — |
| **Conversations** | `Blackboex.Conversations` | Conversation, Run, Event | `ConversationQueries` |
| **ProjectConversations** | `Blackboex.ProjectConversations` | ProjectConversation, ProjectRun, ProjectEvent | `ProjectConversationQueries` |
| **Plans** | `Blackboex.Plans` | Plan, PlanTask | `PlanQueries` |
| **Agent** | `Blackboex.Agent` | — | — |
| **CodeGen** | `Blackboex.CodeGen` | — | — |
| **Billing** | `Blackboex.Billing` | Subscription, UsageEvent, DailyUsage | `BillingQueries` |
| **LLM** | `Blackboex.LLM` | Usage | — |
| **Testing** | `Blackboex.Testing` | TestSuite, TestRequest | `TestingQueries` |
| **Docs** | `Blackboex.Docs` | — | — |
| **Audit** | `Blackboex.Audit` | AuditLog | `AuditQueries` |
| **Policy** | `Blackboex.Policy` | — | — |
| **Telemetry** | `Blackboex.Telemetry` | — | — |
| **Features** | `Blackboex.Features` | — | — |

## Facade Pattern (defdelegate)

All contexts use `defdelegate` in the facade to delegate to sub-modules. External callers NEVER call sub-modules directly.

```elixir
# In Blackboex.Apis (facade):
defdelegate list_files(api), to: Blackboex.Apis.Files
defdelegate create_file(api, attrs), to: Blackboex.Apis.Files
defdelegate create_version(api, attrs), to: Blackboex.Apis.Versions
```

## Public APIs (Key Functions)

### Accounts
- `register_user/1` — creates user + personal org + membership atomically
- `get_user_by_email/1`, `get_user_by_email_and_password/2`, `get_user_by_session_token/1`
- `generate_user_session_token/1`, `delete_user_session_token/1`
- `login_user_by_magic_link/1`, `get_user_by_magic_link_token/1`
- `sudo_mode?/2` — checks if authentication is recent enough
- `update_user_preference(user, path, value) :: {:ok, User.t()} | {:error, Ecto.Changeset.t() | :forbidden}` — writes a leaf value in the `preferences` JSONB blob at the given string-key path; first segment must be in `@preferences_allowed_roots` or returns `{:error, :forbidden}`
- `get_user_preference(user, path, default) :: term()` — reads a value from `preferences` at the given string-key path; returns `default` when any segment is missing

### Organizations
- `create_organization/2` :: `(User.t(), map()) -> {:ok, %{organization, membership}} | {:error, ...}`
- `list_user_organizations/1`, `get_organization!/1`, `get_organization/1`
- `add_member/3`, `get_user_membership/2`
- `invite_member/3`, `accept_invitation/2` — invitation-based onboarding for new/existing users
- New organizations receive one managed sample project named `"Examples"` via `Blackboex.Projects.Samples`.

### Settings
- `setup_completed?/0` — cached singleton check used by `RequireSetup` plug
- `mark_setup_completed!/1`, `get_settings/0`, `invalidate_cache/0`

### Onboarding
- `complete_first_run/1` — atomic first-run wizard transaction (admin user + org + project + instance settings)

### Apis
- `create_api/1`, `list_apis/1`, `get_api/2`, `update_api/2`, `delete_api/1`
- `publish/2`, `unpublish/1` — lifecycle transitions
- `create_version/2`, `rollback_to_version/3`, `list_versions/1`
- `list_files/1`, `create_file/2`, `update_file_content/3`, `upsert_files/3`
- **Removed from Apis:** `start_agent_generation/3`, `start_agent_edit/3` → now in `Agent` facade

### Samples
- `Blackboex.Samples.Manifest` is the single source of truth for platform samples/templates.
- API/Flow template facades read from the manifest. Do not add parallel sample lists in seeds, UI, or contexts.
- Managed sample records carry `sample_uuid`; sync updates by this stable identity.

### Agent
- `Agent.start_generation/3` — entry point for AI code generation
- `Agent.start_edit/3` — entry point for AI code editing

### Conversations
- `get_or_create_conversation/2`, `create_run/1`, `complete_run/2`
- `touch_run/1`, `list_stale_runs/1`, `append_event/1`, `next_sequence/1`

### ProjectAgent (M5)
- `start_planning/3 :: (Project.t(), User.t(), String.t()) -> {:ok, ProjectConversation.t(), ProjectRun.t()} | {:error, term()}` — opens a `ProjectConversation` + `ProjectRun` (`run_type: "plan"`), enqueues `ProjectAgent.KickoffWorker` on `:project_orchestration`.
- `approve_and_run/3 :: (Plan.t(), User.t(), %{markdown_body}) -> {:ok, Plan.t()} | {:error, term()}` — re-validates the markdown via `Plans.approve_plan/3`, transitions `:draft → :approved`, enqueues `PlanRunnerWorker`. Surfaces `{:error, :concurrent_active_plan}` for the partial-unique loser.
- Sub-modules (NOT for direct external use): `Planner` (typed emission via `ReqLLM.Generation.generate_object/4` behind a test seam), `ProjectIndex` (ETS-cached project metadata digest), `KickoffWorker` (creates plan + tasks), `PlanRunnerWorker` (callback-driven advancement on `:project_orchestration`), `BroadcastAdapter` (uniform contract: `subscribe/2`, `handle_terminal/4`, `translate_message/2`, `topic_for/1`).
- Listener pattern: M5 ships **option (b) — Poll-only / runner re-entry** with the `subscribe/2` seam pre-built so an option-(c) per-task GenServer can land later without contract changes. See `lib/blackboex/project_agent/AGENTS.md`.

### Features (M6)
- `project_agent_enabled?/1 :: (Project.t()) -> boolean()` — canonical feature-flag facade. Resolution order, first-wins:
  1. Per-project `Blackboex.ProjectEnvVars` override (`name = "FEATURE_PROJECT_AGENT"`, value `"true"` / `"false"`).
  2. Application config default — `:blackboex, :features` keyword list, key `:project_agent`.
  3. Hard-coded conservative default (`false`).
- Default in `config/dev.exs` and `config/test.exs`: `project_agent: true`. Default in `config/prod.exs`: `project_agent: false`.
- This is the canonical pattern for any new feature flag — keep the module thin (<30 LOC of logic) and add one resolver per flag.

### Plans (Project Agent — M2)
- `list_plans_for_project/2`, `get_plan!/1`, `get_active_plan/1`, `list_tasks/1`, `get_task!/1`
- `create_draft_plan/3` — atomic insert of `Plan` + `PlanTask` rows in `:draft`
- `approve_plan/3` — validates markdown via `MarkdownParser.parse_and_validate/2`; transitions `:draft → :approved`. Translates partial-unique violations as `{:error, :concurrent_active_plan}`. Returns `{:error, {:invalid_markdown_edit, [violation]}}` on edit violations.
- State machine: `mark_plan_running/1`, `mark_plan_done/1`, `mark_plan_partial/2`, `mark_plan_failed/2`
- Task transitions: `mark_task_running/2`, `mark_task_done/1`, `mark_task_failed/2` — `:skipped` is creation-time-only and has no transition function
- `start_continuation/2` — re-plan from a `:partial` or `:failed` parent; copies `:done` tasks as `:skipped` rows on the child; returns `{:error, :parent_still_active}` for non-terminal parents

### MarkdownRenderer / MarkdownParser
- `MarkdownRenderer.render/1 :: Plan.t() -> String.t()` — pure
- `MarkdownParser.parse_and_validate/2 :: (String.t(), Plan.t()) -> {:ok, %{title, tasks}} | {:error, [violation]}`
- Allowed edits: `acceptance_criteria`, `params`, task `title`, reordering. Forbidden: `:invalid_artifact_type`, `:invalid_action`, `:target_artifact_changed`, `:structural_field_renamed`.

### ProjectConversations (M1)
- `get_or_create_active_conversation/2`, `start_new_conversation/2`, `archive_active_conversation/1`
- Run lifecycle: `create_run/1`, `mark_run_running/1`, `complete_run/2`, `fail_run/2`
- Events: `append_event/2`, `list_events/2`, `list_active_conversation_events/2`

### Billing
- `get_subscription/1`, `create_or_update_subscription/1`
- `create_checkout_session/4`, `create_portal_session/2`
- `record_usage_event/1`, `get_daily_usage_for_period/3`

### Audit
- `log/2` — `(action_string, attrs_map)`
- `list_logs/2`, `list_recent_activity/2`
- `track/1` — ExAudit row-level tracking

### CodeGen
- `compile/2` :: `(Api.t(), String.t()) -> {:ok, module()} | {:error, ...}`
- `unload/1`, `module_name_for/1`
- `validate_and_test/3`, `validate_on_save/4`

## GenServers & Supervision

| GenServer | Purpose | Registry |
|-----------|---------|----------|
| `Agent.Session` | One per active run — thin shell, delegates to Session.* | Dynamic, named by run_id |
| `LLM.CircuitBreaker` | Per-provider health tracking | Named by provider atom |
| `Apis.Registry` | Tracks deployed compiled modules | Singleton |

## Oban Workers

| Worker | Queue | Schedule | Purpose |
|--------|-------|----------|---------|
| `Agent.KickoffWorker` | generation (3) | On-demand | Start agent run |
| `Agent.RecoveryWorker` | generation (3) | Every 2 min | Recover stale runs |
| `Billing.UsageAggregationWorker` | billing (10) | Daily | Aggregate usage events |
| `Apis.MetricRollupWorker` | analytics (5) | Hourly | Rollup API metrics |
| `Workers.FlowExecutionWorker` | flows (3) | On-demand | Run a flow execution asynchronously |

## Invariants

1. **Scope always present** — every operation receives `%Scope{user, organization, membership}`
2. **Advisory locks on create_api** — `pg_advisory_xact_lock` prevents race conditions
3. **Conversations are event-sourced** — append-only Events with sequence numbers
4. **Billing gates expensive operations** — `Enforcement.check/2` before create_api, llm_generation
5. **CircuitBreaker protects LLM calls** — 5 failures in 60s opens circuit, 30s recovery
6. **SecurityConfig is single source** — `LLM.SecurityConfig` owns allowed/prohibited module lists

## Test Infrastructure

See root `AGENTS.md § Test Patterns` for the full reference.

**Key rules:**
- `DataCase` auto-imports ALL fixtures + `Mox.verify_on_exit!` — no manual imports needed
- Every schema insert MUST use a fixture function — never inline `%Schema{} |> changeset |> Repo.insert`
- New schema = new fixture function (create BEFORE writing tests)
- Mox for LLM/Stripe — use `setup :stub_llm_client` or `setup :stub_stripe` for defaults
- Oban manual mode — `Oban.Testing.assert_enqueued/2`
