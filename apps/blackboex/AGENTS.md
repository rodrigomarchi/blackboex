# AGENTS.md — Domain App (blackboex)

Pure business logic. Zero Phoenix dependencies. All contexts accessed via facade modules.

## Context Map

| Context | Purpose | Key Schemas |
|---------|---------|-------------|
| **Accounts** | Users, auth tokens, scopes | User, UserToken, Scope |
| **Organizations** | Multi-tenancy, memberships | Organization, Membership |
| **Apis** | Core entity — API definitions + lifecycle | Api, ApiKey, ApiVersion, InvocationLog, MetricRollup |
| **Conversations** | Agent interaction history (event-sourced) | Conversation, Run, Event |
| **Agent** | AI orchestration via LangChain | Session (GenServer), KickoffWorker, CodePipeline |
| **CodeGen** | Compilation/validation pipeline | Compiler, UnifiedPipeline, Linter, AstValidator |
| **Billing** | Stripe integration, usage tracking | Subscription, UsageEvent, DailyUsage |
| **LLM** | Model interface, circuit breaker | CircuitBreaker (GenServer), RateLimiter, Config |
| **Testing** | API test framework | TestRunner, TestGenerator, TestSuite, TestRequest |
| **Docs** | Documentation generation | DocGenerator, OpenApiGenerator |
| **Audit** | Change tracking | AuditLog |
| **Policy** | Authorization (LetMe DSL) | — |

## Public APIs (Key Functions)

### Accounts
- `register_user/1` — creates user + personal org + membership atomically
- `get_user_by_email_and_password/2`, `get_user_by_session_token/1`
- `generate_user_session_token/1`, `delete_user_session_token/1`
- `login_user_by_magic_link/1`

### Organizations
- `create_organization/2` :: `(User.t(), map()) -> {:ok, %{organization, membership}} | {:error, ...}`
- `list_user_organizations/1`, `get_organization!/1`
- `add_member/3`, `get_user_membership/2`, `get_user_primary_plan/1`

### Apis
- `create_api/1` — checks `Billing.Enforcement`, uses advisory lock
- `list_apis/1`, `get_api/2` — scoped by organization_id
- `update_api/2`, `delete_api/1`
- `publish/2`, `unpublish/1` — lifecycle transitions
- `create_version/2`, `rollback_to_version/3`
- `start_agent_generation/3`, `start_agent_edit/3` — triggers AI pipeline

### Conversations
- `get_or_create_conversation/2` — 1:1 with API
- `create_run/1`, `complete_run/2`, `update_run_metrics/2`
- `append_event/1`, `next_sequence/1` — event sourcing
- `list_runs/2`, `list_events/2`, `run_summary_for_context/2`

### Billing
- `get_subscription/1`, `create_or_update_subscription/1`
- `create_checkout_session/4`, `create_portal_session/2`
- `record_usage_event/1`, `get_daily_usage_for_period/3`

### Audit
- `log/2` — `(action_string, attrs_map)`
- `list_logs/2`, `list_recent_activity/2`
- `track/1` — ExAudit row-level tracking

### CodeGen
- `Compiler.compile/2` :: `(Api.t(), String.t()) -> {:ok, module()} | {:error, ...}`
- `Compiler.unload/1`, `Compiler.module_name_for/1`
- `UnifiedPipeline.validate_and_test/3`, `validate_on_save/4`

### Agent
- `Session.start/1` — starts GenServer for a run
- `CodePipeline.run_generation/3`, `run_edit/5` — deterministic pipeline (2-4 LLM calls)
- `KickoffWorker` — Oban entry point, queue: `:generation`

## GenServers & Supervision

| GenServer | Purpose | Registry |
|-----------|---------|----------|
| `Agent.Session` | One per active run, manages LLM chain lifecycle | Dynamic, named by run_id |
| `LLM.CircuitBreaker` | Per-provider health tracking (closed/open/half_open) | Named by provider atom |
| `Apis.Registry` | Tracks deployed compiled modules | Singleton |

## Oban Workers

| Worker | Queue | Schedule | Purpose |
|--------|-------|----------|---------|
| `KickoffWorker` | generation (3) | On-demand | Start agent run |
| `GenerationWorker` | generation (3) | On-demand | Run code generation pipeline |
| `RecoveryWorker` | generation (3) | Every 2 min | Recover stale runs |
| `UsageAggregationWorker` | billing (10) | Daily | Aggregate usage events |
| `MetricRollupWorker` | analytics (5) | Hourly | Rollup API metrics |

## Invariants

1. **Scope always present** — every operation receives `%Scope{user, organization, membership}`
2. **Advisory locks on create_api** — `pg_advisory_xact_lock` prevents race conditions
3. **Conversations are event-sourced** — append-only Events with sequence numbers
4. **Billing gates expensive operations** — `Enforcement.check/2` before create_api, llm_generation
5. **CircuitBreaker protects LLM calls** — 5 failures in 60s opens circuit, 30s recovery
6. **Version numbers inside transaction** — `SELECT MAX(version_number)` inside `Ecto.Multi`

## Test Infrastructure

- `Blackboex.DataCase` — Ecto sandbox setup, `import Blackboex.Factory`
- `Blackboex.Factory` — ExMachina factories for all schemas
- Mox mocks: `Blackboex.LLM.ClientMock`, `Blackboex.Billing.StripeClientMock`
- Oban test mode: `:manual` — assert with `Oban.Testing.assert_enqueued/2`
- Tags: `@tag :unit`, `@tag :integration`
