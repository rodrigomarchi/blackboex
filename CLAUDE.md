# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NUNCA fazer commit sem o usuario pedir explicitamente. Sempre esperar a instrucao 'fazer o commit' ou similar antes de executar git commit.

## Active Technologies

- Elixir 1.19+ / OTP 28+ + Phoenix 1.8+, Phoenix LiveView 1.1+, Ecto 3.x
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

# Database
make db.migrate                # Run pending migrations
make db.rollback               # Rollback last migration
make db.gen.migration NAME=x   # Generate migration
make db.reset                  # Drop + create + migrate + seed
```

## Architecture

Umbrella app with strict domain/web separation. The domain app (`blackboex`) has zero Phoenix dependencies.

### Domain Contexts (`apps/blackboex/lib/blackboex/`)

- **Accounts** — Users, auth tokens, scopes. Multi-tenant via `Scope` (user + organization context).
- **Organizations** — Multi-tenancy: orgs, memberships, org-level access control.
- **Apis** — Core business entity. API definitions with lifecycle: `draft -> compiled -> published -> archived`. Each API has source_code, test_code, documentation, param schemas. `Apis.Registry` GenServer tracks deployed versions.
- **Conversations** — Agent interaction history. 1:1 per API. Event-sourced: Conversation -> Run -> Event. Tracks token usage, costs, total runs/events.
- **Agent** — AI code generation orchestration via LangChain. `Agent.Session` GenServer per run. Entry point: `Agent.KickoffWorker` (Oban). Includes CodeGenChain, EditChain, Guardrails, Tools. `RecoveryWorker` cron recovers failed runs every 2 min.
- **CodeGen** — Compilation/validation pipeline. `UnifiedPipeline` orchestrates Compiler (sandbox), Linter, AstValidator, SchemaExtractor. Runs via `GenerationWorker` (Oban).
- **Billing** — Stripe integration. Subscriptions, usage tracking, enforcement. `UsageAggregationWorker` (Oban). Webhook signature verification.
- **LLM** — Model interface with CircuitBreaker GenServer and RateLimiter. Clients: `ReqLLMClient` (prod) / `ClientMock` (test).
- **Testing** — API test framework: TestRunner, TestGenerator, ResponseValidator, ContractValidator.
- **Docs** — DocGenerator (markdown), OpenApiGenerator (OpenAPI specs).
- **Audit** — Row-level change tracking via ExAudit on: Subscription, Api, ApiKey, Organization.

### Web App (`apps/blackboex_web/lib/blackboex_web/`)

- **LiveViews**: Dashboard, ApiLive (Index/New/Show/Edit/Analytics), ApiKeyLive, BillingLive, SettingsLive
- **Admin**: Backpex-powered at `/admin` — users, apis, orgs, subscriptions, audit logs
- **Dynamic API routing**: `/api/*` forwarded to `DynamicApiRouter` which dispatches to deployed API versions
- **Public**: `/p/:org_slug/:api_slug` serves published API documentation
- **Layouts**: Root, App, Editor (for API editing), Admin, Auth
- **Components**: CoreComponents, CommandPalette, ChatPanel, RequestBuilder, LiveMonacoEditor

### Key Patterns

- **PubSub**: Real-time updates broadcast on `api:#{api_id}` topic
- **Oban queues**: `billing` (10), `analytics` (5), `generation` (3). Cron: MetricRollupWorker (hourly), RecoveryWorker (every 2 min)
- **Advisory locks**: `pg_advisory_xact_lock` for API creation consistency
- **Feature flags**: `fun_with_flags` (e.g., `:agent_pipeline`)
- **Multi-tenant auth**: `SetOrganization` on_mount hook loads org from session

### Test Patterns

- **Factories**: ExMachina via `Blackboex.Factory`
- **Mocks**: Mox for LLM client (`ClientMock`) and Stripe (`StripeClientMock`)
- **Sandbox**: `Blackboex.DataCase` sets up Ecto SQL sandbox
- **Oban**: Test mode `:manual` — jobs don't auto-execute, use `Oban.Testing`
- **Tags**: `@tag :unit`, `@tag :integration`, `@tag :liveview`

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
