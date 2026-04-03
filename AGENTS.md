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
- `apps/blackboex/lib/blackboex/agent/AGENTS.md` — AI agent pipeline
- `apps/blackboex/lib/blackboex/code_gen/AGENTS.md` — Compilation/validation pipeline
- `apps/blackboex/lib/blackboex/billing/AGENTS.md` — Stripe/billing
- `apps/blackboex_web/AGENTS.md` — Web layer, routing, components

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

## Never Do This

- Compile user code outside the sandbox (CodeGen.Compiler)
- Use `String.to_atom/1` with external data — use Map lookup instead
- Skip ownership checks when fetching resources (IDOR vulnerability)
- Return internal error details to users — log internally, show generic message
- Use `==` to compare secrets — use `Plug.Crypto.secure_compare/2`
- Use `send(self())` for IO/network work in LiveView processes
- Call domain modules directly from templates — go through context facades
- Run `Repo.get!` with session/external data — use `Repo.get` + pattern match

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

- **Factories:** ExMachina base in `Blackboex.Factory`. Test data primarily via fixtures in `test/support/fixtures/`
- **Mocks:** Mox — define expectations before test, verify on exit
- **Sandbox:** `Blackboex.DataCase` sets up Ecto SQL sandbox
- **Oban:** Test mode `:manual` — use `Oban.Testing.assert_enqueued/2`
- **Tags:** `@moduletag :unit`, `@moduletag :integration`, `@moduletag :liveview`, `@tag :capture_log`
- **Async:** Tests using Mox mocks must set `async: false`

## Config Environments

| Aspect | Dev | Test | Prod |
|--------|-----|------|------|
| LLM | Real client | ClientMock | Real client |
| Stripe | Real client | StripeClientMock | Real client |
| DB port | 5434 | 5435 | DATABASE_URL |
| Oban | Normal | Manual mode | Normal |
| OTel | Disabled | Disabled | 10% sampling |
