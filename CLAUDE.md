# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NUNCA fazer commit sem o usuario pedir explicitamente. Sempre esperar a instrucao 'fazer o commit' ou similar antes de executar git commit.

## Active Technologies

- Elixir ~> 1.15 / OTP 26+ + Phoenix 1.8+, Phoenix LiveView ~> 1.1, Ecto 3.x
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

Umbrella app with strict domain/web separation. See `AGENTS.md` for full context map, inter-context dependencies, data flows, test patterns, and config differences.

## Development Workflow — Mandatory Rules

- **TDD mandatory** — Write tests FIRST, see them fail, then implement. No exceptions.
- **Always run `make test` + `make lint`** after every change. Fix ALL issues including pre-existing ones.
- **Zero warnings policy** — Never ignore Credo [D] design warnings. Never dismiss Dialyzer warnings without root cause investigation.
- **Living documentation** — Update AGENTS.md when adding/changing modules, functions, components, or patterns. Drift causes AI agents to generate wrong code.

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

### AGENTS.md Hierarchy (always consult before generating code)

```
AGENTS.md                                          — Root: stack, structure, critical rules
├── apps/blackboex/AGENTS.md                       — Domain: context map, public APIs, invariants
│   ├── lib/blackboex/accounts/AGENTS.md           — Auth, Scope, UserToken, multi-tenancy
│   ├── lib/blackboex/apis/AGENTS.md               — Core entity, lifecycle, Registry, deployment
│   ├── lib/blackboex/agent/AGENTS.md              — AI pipeline, Session, CodePipeline
│   ├── lib/blackboex/billing/AGENTS.md            — Stripe, enforcement, webhooks
│   ├── lib/blackboex/code_gen/AGENTS.md           — Compiler, sandbox, validation
│   ├── lib/blackboex/conversations/AGENTS.md      — Event-sourced runs/events
│   ├── lib/blackboex/docs/AGENTS.md               — DocGenerator, OpenAPI
│   ├── lib/blackboex/features/AGENTS.md           — FunWithFlags, feature flags
│   ├── lib/blackboex/llm/AGENTS.md                — CircuitBreaker, RateLimiter, prompts
│   ├── lib/blackboex/organizations/AGENTS.md      — Multi-tenancy, memberships
│   ├── lib/blackboex/policy/AGENTS.md             — LetMe DSL, authorization
│   ├── lib/blackboex/telemetry/AGENTS.md          — OpenTelemetry, events
│   ├── lib/blackboex/testing/AGENTS.md            — TestRunner, TestGenerator, validation
│   └── lib/blackboex/audit/AGENTS.md              — ExAudit, AuditLog
├── apps/blackboex_web/AGENTS.md                   — Web: routing, auth flow, plugs
│   ├── lib/blackboex_web/components/AGENTS.md     — FULL component catalog (SaladUI + shared + editor)
│   ├── lib/blackboex_web/live/AGENTS.md           — LiveView patterns + catalog of all views
│   ├── lib/blackboex_web/admin/AGENTS.md          — Backpex admin, 23 LiveResources
│   ├── lib/blackboex_web/plugs/AGENTS.md          — All custom plugs, composition order
│   └── lib/blackboex_web/controllers/AGENTS.md    — Controllers, UserAuth, hooks
```

**Rule:** Before generating code in ANY area, read the relevant AGENTS.md first. The component catalog (`components/AGENTS.md`) is especially critical — all UI must be compositions of existing components.
