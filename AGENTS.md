# AGENTS.md — Blackboex

## What Is This

Blackboex is a platform where users describe APIs in natural language and an AI agent generates, compiles, tests, and publishes them as live HTTP endpoints. Built as an Elixir umbrella app with strict domain/web separation.

## Stack

- Elixir 1.19+ / OTP 28+ / Phoenix 1.8+ / LiveView 1.1+ / Ecto 3.x
- PostgreSQL 16+ / Oban (async jobs) / PubSub (real-time)
- Tailwind CSS + esbuild (no npm for build) / SaladUI + Backpex
- LangChain for AI orchestration

## Project Structure

```
apps/blackboex/       — Domain app (zero Phoenix deps). Business logic, schemas, workers.
apps/blackboex_web/   — Web app. Phoenix, LiveView, admin panel, dynamic API routing.
config/               — Shared + per-env configuration
docs/                 — Architecture, plans, discovery docs
infra/                — Docker, deployment
```

## Structural Patterns — Mandatory

### Context Decomposition
- Every context with data has: **facade** (`defdelegate`) + **\*Queries module** + sub-contexts if >300 lines
- Facade is the public API. External callers (web, workers) **NEVER** import sub-modules directly
- `*Queries` modules contain ONLY query builders (`import Ecto.Query`). No side effects, no `Repo` calls inside queries
- Sub-contexts contain business logic. They call `*Queries` for data access
- Schemas stay in their own files with changesets. Schemas NEVER move paths

### When to Decompose
- Context facade > 300 lines → extract sub-contexts with `defdelegate`
- 3+ inline `Ecto.Query` calls → extract to `*Queries` module
- GenServer > 200 lines → extract logic into sub-modules, keep GenServer as thin shell
- Pipeline/workflow > 400 lines → split by phase/responsibility

### Naming Conventions
- Context facade: `Blackboex.Apis` (singular namespace, plural for collections)
- Sub-context: `Blackboex.Apis.Files`, `Blackboex.Apis.Versions`
- Query module: `Blackboex.Apis.FileQueries`, `Blackboex.Apis.VersionQueries`
- Schema: `Blackboex.Apis.Api`, `Blackboex.Apis.ApiFile` (singular)
- Worker: stays at current path, never rename (Oban jobs reference module name)

### Security
- `Blackboex.LLM.SecurityConfig` is the SINGLE source for allowed/prohibited modules
- Never duplicate these lists. Always reference `SecurityConfig`

## Sub-AGENTS.md Index

- `apps/blackboex/AGENTS.md` — Domain contexts, public APIs, invariants
- `apps/blackboex/lib/blackboex/accounts/AGENTS.md` — Auth, Scope, UserToken, UserQueries
- `apps/blackboex/lib/blackboex/apis/AGENTS.md` — Core entity, sub-contexts, lifecycle, Registry
- `apps/blackboex/lib/blackboex/flows/AGENTS.md` — Visual workflow flows, Drawflow editor, CRUD
- `apps/blackboex/lib/blackboex/agent/AGENTS.md` — AI agent facade, Pipeline.*, Session.*
- `apps/blackboex/lib/blackboex/code_gen/AGENTS.md` — Compiler, sandbox, DiffEngine
- `apps/blackboex/lib/blackboex/conversations/AGENTS.md` — Event-sourced runs/events, ConversationQueries
- `apps/blackboex/lib/blackboex/docs/AGENTS.md` — Docs facade, DocGenerator, OpenAPI
- `apps/blackboex/lib/blackboex/features/AGENTS.md` — Feature flags
- `apps/blackboex/lib/blackboex/llm/AGENTS.md` — LLM facade, SecurityConfig, CircuitBreaker
- `apps/blackboex/lib/blackboex/organizations/AGENTS.md` — Multi-tenancy, OrganizationQueries
- `apps/blackboex/lib/blackboex/policy/AGENTS.md` — LetMe authorization
- `apps/blackboex/lib/blackboex/telemetry/AGENTS.md` — OpenTelemetry, events
- `apps/blackboex/lib/blackboex/pages/AGENTS.md` — Pages context, Markdown content
- `apps/blackboex/lib/blackboex/playgrounds/AGENTS.md` — Playgrounds context, Executor sandbox, `record_ai_edit/3`
- `apps/blackboex/lib/blackboex/playground_agent/AGENTS.md` — AI chat pipeline for Playgrounds (Session, ChainRunner, CodePipeline, Prompts)
- `apps/blackboex/lib/blackboex/playground_conversations/AGENTS.md` — Persisted chat conversations/runs/events for the Playground agent
- `apps/blackboex/lib/blackboex/page_agent/AGENTS.md` — AI chat pipeline for Pages (markdown editor agent: Session, ChainRunner, ContentPipeline, Prompts)
- `apps/blackboex/lib/blackboex/page_conversations/AGENTS.md` — Persisted chat conversations/runs/events for the Page agent
- `apps/blackboex/lib/blackboex/flow_executions/AGENTS.md` — FlowExecution + NodeExecution schemas, status state machine, execution lifecycle API
- `apps/blackboex/lib/blackboex/project_env_vars/AGENTS.md` — Project-scoped env vars and LLM integration keys (replaces FlowSecrets)
- `apps/blackboex/lib/blackboex/projects/AGENTS.md` — Project grouping within orgs, ProjectMembership roles, access rules
- `apps/blackboex/lib/blackboex/samples/AGENTS.md` — Unified samples/templates manifest
- `Blackboex.Samples.Manifest` — single source of truth for platform samples/templates used by APIs, Flows, initial workspaces, seeds, and sync tasks
- `apps/blackboex/lib/blackboex/workers/AGENTS.md` — Oban background workers (FlowExecutionWorker), queue names, enqueue patterns
- `apps/blackboex/lib/blackboex/testing/AGENTS.md` — TestRunner, TestingQueries
- `apps/blackboex/lib/blackboex/audit/AGENTS.md` — ExAudit, AuditQueries
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
6. **Mox for external services** — `ClientMock` (LLM)
7. **Oban for background jobs** — never spawn unsupervised processes for business logic
8. **TDD mandatory** — write tests FIRST, see them fail, then implement. No exceptions.
9. **Always run `make test` + `make lint` after changes** — fix ALL issues including pre-existing ones
10. **Keep AGENTS.md in sync** — update when adding/changing modules, functions, components, or patterns

## Inter-Context Dependencies

```
Agent ──→ CodeGen, LLM, Conversations, Apis, Testing, Docs
CodeGen ──→ LLM
Apis ──→ CodeGen.Compiler, Audit
Accounts ──→ Organizations (creates personal org on registration)
```

## First-run Onboarding

A first-run setup wizard at `/setup` (`apps/blackboex_web/lib/blackboex_web/live/setup_live.ex`) bootstraps the platform admin user, organization, and project on a fresh database. Until completed, the `BlackboexWeb.Plugs.RequireSetup` plug redirects browser traffic to `/setup`. Public registration (`/users/register`) has been removed; new users join via invitation links (`/invitations/:token`).

## Key Data Flows

**1. Agent Generation:** User message → `Agent.start_generation/3` → Oban `KickoffWorker` → `Agent.Session` GenServer → `Agent.Pipeline.*` (2-4 LLM calls) → `Conversations` event persistence → PubSub broadcast → LiveView update

**2. API Invocation:** HTTP `POST /api/*` → `DynamicApiRouter` → `ApiAuth` (key verification) → `RateLimiter` (4 layers) → Sandbox execution → JSON response

## Test Patterns

### Fixture-First Policy (mandatory)

**Never create entities inline** with `%Schema{} |> changeset |> Repo.insert`. Always use fixture functions. All fixtures are auto-imported via `DataCase` (domain) and `ConnCase` (web) — no manual imports needed.

```
test/support/
├── data_case.ex                          — Auto-imports all fixtures + Mox.verify_on_exit!
├── mock_defaults.ex                      — stub_llm_client/1 (named setups)
├── mocks.ex                              — Mox.defmock definitions
└── fixtures/
    ├── accounts_fixtures.ex              — user_fixture/1, user_scope_fixture/0,1
    ├── organizations_fixtures.ex         — org_fixture/1, user_and_org_fixture/1, named setups: create_user_and_org, create_org
    ├── apis_fixtures.ex                  — api_fixture/1, api_key_fixture/2, invocation_log_fixture/1, metric_rollup_fixture/1, named setups: create_api, create_org_and_api
    ├── conversations_fixtures.ex        — conversation_fixture/2, run_fixture/1
    └── testing_fixtures.ex              — test_suite_fixture/1
```

### Composable Named Setups

```elixir
# Web tests: compose login + data setup in one line
setup [:register_and_log_in_user, :create_org_and_api]

# Domain tests: user + org
setup :create_user_and_org
```

### What NOT to do in tests

- No `import Blackboex.AccountsFixtures` — already auto-imported
- No `import Phoenix.LiveViewTest` — already auto-imported via ConnCase
- No `import Mox` + `setup :verify_on_exit!` — already automatic in DataCase
- No `defp create_org`, `defp build_api`, `defp insert_log` — use shared fixtures
- No `%Schema{} |> changeset |> Repo.insert` — use `*_fixture()` functions

### Mocks

- Mox — `ClientMock` (LLM)
- `Mox.verify_on_exit!` is automatic in DataCase — no manual setup needed
- Only add `import Mox` if tests use `expect/3` or `stub/3` directly
- Use `setup :stub_llm_client` for default LLM stubs

### Other

- **Sandbox:** `Blackboex.DataCase` for Ecto SQL sandbox
- **Test DB reset:** `mix test` / `make test` drops, recreates, and migrates `blackboex_test` before running tests. Keep this behavior so PostgreSQL bloat from rolled-back sandbox inserts does not accumulate across runs.
- **Index coverage:** `Blackboex.Repo.IndexCoverageTest` verifies every foreign key has a leading supporting index. Add indexes with new foreign keys.
- **Oban:** Manual mode — use `Oban.Testing.assert_enqueued/2`
- **Tags:** `@moduletag :unit`, `:integration`, `:liveview`, `@tag :capture_log`
- **New schema = new fixture:** when adding a schema that will be inserted in tests, create the fixture BEFORE writing tests
