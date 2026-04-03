# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NUNCA fazer commit sem o usuario pedir explicitamente. Sempre esperar a instrucao 'fazer o commit' ou similar antes de executar git commit.

## Active Technologies

- Elixir ~> 1.15 / OTP 26+ + Phoenix 1.8+, Phoenix LiveView ~> 1.0, Ecto 3.x
- PostgreSQL 16+ via Ecto
- Tailwind CSS + esbuild for asset bundling (no npm for build)
- SaladUI component library + Backpex (admin panel)
- Bandit HTTP server

## Commands

```bash
make setup                     # First-time setup (docker + deps + db)
make server                    # Dev server (localhost:4000)
make test                      # Full test suite
make lint                      # All static analysis (format + credo + dialyzer)
make precommit                 # compile + format + test

# Targeted testing
mix test path/to/test.exs      # Single file
mix test path/to/test.exs:42   # Single test by line
make test.domain               # Domain app only
make test.web                  # Web app only
make test.failed               # Re-run failed tests
make test.unit                 # Only @moduletag :unit
make test.integration          # Only @moduletag :integration
make test.liveview             # Only @moduletag :liveview
make test.cover                # Coverage report

# Database
make db.migrate                # Run pending migrations
make db.rollback               # Rollback last migration
make db.gen.migration NAME=x   # Generate migration
make db.reset                  # Drop + create + migrate + seed

# Utilities
make routes                    # List all routes
make iex                       # Interactive console
make docker.up                 # Start Docker services
make docker.down               # Stop Docker services
make docker.reset              # Reset Docker volumes
```

## Architecture

Umbrella app with strict domain/web separation. The domain app (`blackboex`) has zero Phoenix dependencies.

### Domain Contexts (`apps/blackboex/lib/blackboex/`)

- **Accounts** — Users, auth tokens, scopes. Multi-tenant via `Accounts.Scope` (user + organization context). Modules: `User`, `UserToken`, `UserNotifier`, `Scope`.
- **Organizations** — Multi-tenancy: orgs, memberships, org-level access control. Modules: `Organization`, `Membership`.
- **Apis** — Core business entity. API definitions with lifecycle: `draft -> compiled -> published -> archived`. Modules: `Api`, `ApiKey`, `ApiVersion`, `Analytics`, `DashboardQueries`, `DataStore`, `DataStore.Entry`, `Deployer`, `DiffEngine`, `InvocationLog`, `Keys`, `MetricRollup`, `MetricRollupWorker`, `Registry` (GenServer tracking deployed versions).
- **Conversations** — Agent interaction history. 1:1 per API. Event-sourced: Conversation -> Run -> Event. Tracks token usage, costs, total runs/events. Modules: `Conversation`, `Run`, `Event`.
- **Agent** — AI code generation orchestration via LangChain. `Agent.Session` GenServer per run. Entry point: `Agent.KickoffWorker` (Oban). `CodePipeline` for deterministic generation (2-4 LLM calls). `FixPrompts` for retry logic. `RecoveryWorker` cron recovers failed runs every 2 min.
- **CodeGen** — Compilation/validation pipeline. `UnifiedPipeline` orchestrates `Compiler`, `Sandbox`, `Linter`, `AstValidator`, `SchemaExtractor`. Also: `Pipeline` (classification), `ModuleBuilder`, `GenerationResult`, `UnifiedPrompts`. Called by Agent.CodePipeline and Agent.Session.
- **Billing** — Stripe integration. Modules: `Subscription`, `UsageEvent`, `DailyUsage`, `ProcessedEvent`, `Enforcement` (plan limit gates), `StripeClient` (behaviour) + `StripeClient.Live` (prod impl), `WebhookHandler`, `UsageAggregationWorker` (Oban, on-demand).
- **LLM** — Model interface with `CircuitBreaker` GenServer and `RateLimiter`. Behaviour: `ClientBehaviour`. Clients: `ReqLLMClient` (prod). Also: `Config`, `Prompts`, `EditPrompts`, `Templates`, `StreamHandler`, `Usage`, `schemas/GeneratedEndpoint`.
- **Testing** — API test framework. Modules: `TestRunner`, `TestGenerator`, `TestSuite`, `TestRequest`, `TestPrompts`, `ResponseValidator`, `ContractValidator`, `RequestExecutor`, `SampleData`, `SnippetGenerator`, `TestFormatter`, `SandboxCase`.
- **Docs** — `DocGenerator` (markdown), `OpenApiGenerator` (OpenAPI specs), `DocPrompts`.
- **Audit** — Row-level change tracking via ExAudit. Modules: `AuditLog`, `Version`. Tracked schemas: Subscription, Api, ApiKey, Organization.
- **Policy** — Authorization via LetMe DSL. Module: `Checks`. Policy checks used by contexts.
- **Telemetry** — `Telemetry.Events` for OpenTelemetry instrumentation and safe event emission.
- **Features** — FunWithFlags integration. Modules: `features/ActorImpl`, `features/GroupImpl` (user-based and plan-based flag targeting).

### Web App (`apps/blackboex_web/lib/blackboex_web/`)

- **LiveViews**: Dashboard, ApiLive (Index/New/Show/Edit/Analytics), ApiKeyLive (Index/Show), BillingLive (Plans/Manage), SettingsLive, UserLive (Registration/Login/Confirmation/Settings)
- **Controllers**: `PageController`, `UserSessionController`, `WebhookController` (Stripe), `PublicApiController`, `ErrorHtml`, `ErrorJson`
- **Admin**: Backpex-powered at `/admin` — 23 LiveResource modules (users, user_tokens, orgs, memberships, apis, api_keys, api_versions, agent conversations/runs/events, data_store entries, invocation_logs, metric_rollups, test_requests/suites, daily_usage, usage_events, processed_events, audit_logs, versions, llm_usage, subscriptions)
- **Dynamic API routing**: `/api/*` forwarded to `DynamicApiRouter` plug which dispatches to deployed API versions
- **Public**: `/p/:org_slug/:api_slug` via `PublicApiController` serves published API documentation
- **Layouts**: Root, AdminRoot, App, Editor (for API editing), Admin, Auth
- **Components**: CoreComponents, ChatPanel, RequestBuilder, ResponseViewer, EditorToolbar, CommandPalette, ValidationDashboard, StatusBar, RightPanel, BottomPanel, Charts, Logo + `ui/` directory with SaladUI components (button, input, card, badge, avatar, dropdown_menu, sheet, sidebar, tabs, tooltip, skeleton, etc.)
- **Plugs**: `ApiAuth`, `DynamicApiRouter`, `RateLimiter`, `SetOrganization`, `AuditContext`, `RequirePlatformAdmin`, `CacheBodyReader`, `HealthCheck`, `ApiDocsPlug`
- **Infrastructure**: `PromEx` (Prometheus metrics), `BeamMonitor` (BEAM VM monitoring), `RateLimiterBackend` (ETS-based)

### Key Patterns

- **PubSub**: Real-time updates broadcast on `api:#{api_id}` topic
- **Oban queues**: `billing` (10), `analytics` (5), `generation` (3). Cron: `Apis.MetricRollupWorker` (hourly), `Agent.RecoveryWorker` (every 2 min). On-demand: `Agent.KickoffWorker`, `Billing.UsageAggregationWorker`
- **Advisory locks**: `pg_advisory_xact_lock` for API creation consistency
- **Feature flags**: `fun_with_flags` (e.g., `:agent_pipeline`)
- **Multi-tenant auth**: `SetOrganization` on_mount hook loads org from session

### Test Patterns

- **Factories**: ExMachina via `Blackboex.Factory`
- **Mocks**: Mox for LLM (`ClientBehaviour` → `ClientMock`) and Stripe (`StripeClient` → `StripeClientMock`)
- **Sandbox**: `Blackboex.DataCase` sets up Ecto SQL sandbox
- **Oban**: Test mode `:manual` — jobs don't auto-execute, use `Oban.Testing`
- **Tags**: `@moduletag :unit`, `@moduletag :integration`, `@moduletag :liveview`, `@tag :capture_log`

### Config Differences

- **Dev**: Real LLM client, PostgreSQL on port 5434, OpenTelemetry disabled
- **Test**: Mock LLM + Stripe clients, PostgreSQL on port 5435, Oban manual mode, FunWithFlags cache disabled
- **Prod**: Env vars for DATABASE_URL, Stripe keys, ANTHROPIC_API_KEY, OPENAI_API_KEY. Postmark mailer. OTLP tracing with 10% sampling

## Code Style

- Every public function MUST have `@spec`
- LiveViews MUST be thin — delegate to domain contexts
- Credo strict mode enforced
- Dialyzer from day one
- Two esbuild/tailwind targets: `blackboex_web` and `blackboex_admin`

## Dangerous Operations — Never Do This

- Compile user code outside the sandbox (`CodeGen.Compiler`)
- Use `String.to_atom/1` with external data — use Map lookup instead
- Skip ownership checks when fetching resources (IDOR vulnerability)
- Return internal error details to users — log internally, show generic message
- Use `==` to compare secrets — use `Plug.Crypto.secure_compare/2`
- Use `send(self(), :blocking_work)` for IO/network in LiveView — use `Task.async`
- Call domain modules directly from templates — go through context facades
- Run `Repo.get!` with session/external data — use `Repo.get` + pattern match
- Mark webhook as processed BEFORE handling — order is: check → process → mark

## Deep Reference

- `AGENTS.md` — hierarchical AI agent context (root + per-directory)
- `docs/architecture.md` — context diagrams, data flows, supervision tree, invariants
- `docs/gotchas.md` — consolidated gotchas from all 10 development phases
