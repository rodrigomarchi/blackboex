# AGENTS.md — Domain App (blackboex)

Pure business logic. Zero Phoenix dependencies. All contexts accessed via facade modules.

Each context has its own AGENTS.md — **read it before generating code in that area.**

## Context Map

| Context | Facade | Key Schemas | Query Module |
|---------|--------|-------------|--------------|
| **Accounts** | `Blackboex.Accounts` | User, UserToken, Scope | `UserQueries` |
| **Organizations** | `Blackboex.Organizations` | Organization, Membership | `OrganizationQueries` |
| **Apis** | `Blackboex.Apis` | Api, ApiKey, ApiVersion, ApiFile | `ApiQueries`, `FileQueries`, `VersionQueries` |
| **Flows** | `Blackboex.Flows` | Flow | `FlowQueries` |
| **Conversations** | `Blackboex.Conversations` | Conversation, Run, Event | `ConversationQueries` |
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

### Organizations
- `create_organization/2` :: `(User.t(), map()) -> {:ok, %{organization, membership}} | {:error, ...}`
- `list_user_organizations/1`, `get_organization!/1`, `get_organization/1`
- `add_member/3`, `get_user_membership/2`, `get_user_primary_plan/1`

### Apis
- `create_api/1`, `list_apis/1`, `get_api/2`, `update_api/2`, `delete_api/1`
- `publish/2`, `unpublish/1` — lifecycle transitions
- `create_version/2`, `rollback_to_version/3`, `list_versions/1`
- `list_files/1`, `create_file/2`, `update_file_content/3`, `upsert_files/3`
- **Removed from Apis:** `start_agent_generation/3`, `start_agent_edit/3` → now in `Agent` facade

### Agent
- `Agent.start_generation/3` — entry point for AI code generation
- `Agent.start_edit/3` — entry point for AI code editing

### Conversations
- `get_or_create_conversation/2`, `create_run/1`, `complete_run/2`
- `touch_run/1`, `list_stale_runs/1`, `append_event/1`, `next_sequence/1`

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
