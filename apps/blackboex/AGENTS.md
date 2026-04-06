# AGENTS.md — Domain App (blackboex)

Pure business logic. Zero Phoenix dependencies. All contexts accessed via facade modules.

Each context has its own AGENTS.md — **read it before generating code in that area.**

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
| **Telemetry** | OpenTelemetry instrumentation, safe event emission | Events |
| **Features** | FunWithFlags integration (user/plan-based flag targeting) | ActorImpl, GroupImpl |

## Public APIs (Key Functions)

### Accounts
- `register_user/1` — creates user + personal org + membership atomically
- `get_user_by_email/1`, `get_user_by_email_and_password/2`, `get_user_by_session_token/1`
- `generate_user_session_token/1`, `delete_user_session_token/1`
- `login_user_by_magic_link/1`, `get_user_by_magic_link_token/1`
- `change_user_password/3`, `update_user_password/2`
- `change_user_email/3`, `update_user_email/2`
- `deliver_login_instructions/2`, `deliver_user_update_email_instructions/3`
- `sudo_mode?/2` — checks if authentication is recent enough

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
- `touch_run/1` — heartbeat timestamp for recovery detection
- `list_stale_runs/1` — finds runs >120s without heartbeat (used by RecoveryWorker)
- `append_event/1`, `next_sequence/1` — event sourcing
- `list_runs/2`, `list_events/2`
- `get_conversation/1`, `get_conversation_by_api/1`

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

See root `AGENTS.md § Test Patterns` for the full reference.

**Key rules:**
- `DataCase` auto-imports ALL fixtures + `Mox.verify_on_exit!` — no manual imports needed
- Every schema insert MUST use a fixture function from `test/support/fixtures/` — never inline `%Schema{} |> changeset |> Repo.insert`
- New schema = new fixture function (create BEFORE writing tests)
- Mox for LLM/Stripe — use `setup :stub_llm_client` or `setup :stub_stripe` for defaults
- Oban manual mode — `Oban.Testing.assert_enqueued/2`
