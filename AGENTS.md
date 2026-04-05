# AGENTS.md — Blackboex

## What Is This

Blackboex is a platform where users describe APIs in natural language and an AI agent generates, compiles, tests, and publishes them as live HTTP endpoints. Built as an Elixir umbrella app with strict domain/web separation.

## Stack

- Elixir 1.19+ / OTP 28+ / Phoenix 1.8+ / LiveView 1.1+ / Ecto 3.x
- PostgreSQL 16+ / Oban (async jobs) / PubSub (real-time)
- Tailwind CSS + esbuild (no npm for build) / SaladUI + Backpex
- LangChain for AI orchestration / Stripe for billing

## Project Structure

```
apps/blackboex/       — Domain app (zero Phoenix deps). Business logic, schemas, workers.
apps/blackboex_web/   — Web app. Phoenix, LiveView, admin panel, dynamic API routing.
config/               — Shared + per-env configuration
docs/                 — Architecture, plans, discovery docs
infra/                — Docker, deployment
```

See sub-AGENTS.md for deeper context:
- `apps/blackboex/AGENTS.md` — Domain contexts, public APIs, invariants
- `apps/blackboex/lib/blackboex/accounts/AGENTS.md` — Auth, Scope, UserToken
- `apps/blackboex/lib/blackboex/apis/AGENTS.md` — Core entity, lifecycle, Registry
- `apps/blackboex/lib/blackboex/agent/AGENTS.md` — AI agent pipeline
- `apps/blackboex/lib/blackboex/billing/AGENTS.md` — Stripe/billing
- `apps/blackboex/lib/blackboex/code_gen/AGENTS.md` — Compilation/validation pipeline
- `apps/blackboex/lib/blackboex/conversations/AGENTS.md` — Event-sourced runs/events
- `apps/blackboex/lib/blackboex/docs/AGENTS.md` — DocGenerator, OpenAPI
- `apps/blackboex/lib/blackboex/features/AGENTS.md` — Feature flags
- `apps/blackboex/lib/blackboex/llm/AGENTS.md` — CircuitBreaker, prompts
- `apps/blackboex/lib/blackboex/organizations/AGENTS.md` — Multi-tenancy
- `apps/blackboex/lib/blackboex/policy/AGENTS.md` — LetMe authorization
- `apps/blackboex/lib/blackboex/telemetry/AGENTS.md` — OpenTelemetry, events
- `apps/blackboex/lib/blackboex/testing/AGENTS.md` — TestRunner, validation
- `apps/blackboex/lib/blackboex/audit/AGENTS.md` — ExAudit, AuditLog
- `apps/blackboex_web/AGENTS.md` — Web layer, routing, auth flow
- `apps/blackboex_web/lib/blackboex_web/components/AGENTS.md` — **FULL component catalog** (read before ANY UI work)
- `apps/blackboex_web/lib/blackboex_web/live/AGENTS.md` — LiveView patterns + catalog
- `apps/blackboex_web/lib/blackboex_web/admin/AGENTS.md` — Backpex admin panel
- `apps/blackboex_web/lib/blackboex_web/plugs/AGENTS.md` — Custom plugs
- `apps/blackboex_web/lib/blackboex_web/controllers/AGENTS.md` — Controllers, UserAuth, hooks

## Essential Commands

```bash
make setup        # First-time: docker + deps + db
make server       # Dev server at localhost:4000
make test         # Full test suite
make lint         # format + credo --strict + dialyzer
make precommit    # compile + format + test
make test.domain  # Domain app only
make test.web     # Web app only
```

## Critical Rules

1. **Domain app has ZERO Phoenix dependencies** — never import Phoenix modules there
2. **Every public function MUST have `@spec`**
3. **Credo strict mode + Dialyzer** — both must pass before any merge
4. **LiveViews MUST be thin** — delegate all logic to domain contexts
5. **All async work uses Task.async** — never `send(self(), :blocking_work)` in LiveView
6. **Mox for external services** — `ClientMock` (LLM), `StripeClientMock` (Stripe)
7. **Oban for background jobs** — never spawn unsupervised processes for business logic
8. **TDD mandatory** — write tests FIRST, see them fail, then implement. No exceptions.
9. **Always run `make test` + `make lint` after changes** — fix ALL issues including pre-existing ones
10. **Keep AGENTS.md in sync** — update documentation when adding/changing modules, functions, components, or patterns

## Inter-Context Dependencies

```
Agent ──→ CodeGen, LLM, Conversations, Apis, Testing, Docs
CodeGen ──→ LLM, Billing.Enforcement
Apis ──→ Billing.Enforcement, CodeGen.Compiler, Audit
Billing ──→ Audit, Organizations
Accounts ──→ Organizations (creates personal org on registration)
```

## Key Data Flows

**1. Agent Generation:** User message → `Apis.start_agent_generation/3` → Oban `KickoffWorker` → `Agent.Session` GenServer → LangChain LLM loop with 6 tools (compile_code, format_code, lint_code, generate_tests, run_tests, submit_code) OR deterministic `CodePipeline` (2-4 LLM calls) → `Conversations` event persistence → PubSub broadcast → LiveView update

**2. API Invocation:** HTTP `POST /api/*` → `DynamicApiRouter` → `ApiAuth` (key verification) → `RateLimiter` (4 layers) → `Billing.Enforcement` → Sandbox execution → JSON response

**3. Billing:** Stripe Checkout → Webhook → `Billing.create_or_update_subscription/1` → `Enforcement` gates (create_api, llm_generation) → `UsageAggregationWorker` (daily rollup)

## Test Patterns

- **Factories:** ExMachina via `Blackboex.Factory` + fixtures in `test/support/fixtures/`
- **Mocks:** Mox — `ClientMock` (LLM), `StripeClientMock` (Stripe). Tests with Mox must set `async: false`
- **Sandbox:** `Blackboex.DataCase` for Ecto SQL sandbox
- **Oban:** Manual mode — use `Oban.Testing.assert_enqueued/2`
- **Tags:** `@moduletag :unit`, `:integration`, `:liveview`, `@tag :capture_log`
