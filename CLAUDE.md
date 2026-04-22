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
- **Documentation is part of the task** — Every code change is INCOMPLETE until documentation is updated. Do NOT mark any task as done, do NOT move to the next step, do NOT respond with "done" until you have checked and updated:
  - New public function or `@spec` → add to `## Public API` table in the context's `AGENTS.md`
  - New module or context → create `AGENTS.md` for that directory; add entry to root `AGENTS.md` hierarchy
  - New LiveView component → add to `components/AGENTS.md` catalog with all attrs
  - New fixture function → update `CLAUDE.md` fixture table
  - New named setup helper → update `CLAUDE.md` named setups list
  - New JS hook → update `assets/js/hooks/AGENTS.md`
  - New on_mount hook → update `hooks/AGENTS.md`

## Code Style

- Every public function MUST have `@spec`
- LiveViews MUST be thin — delegate to domain contexts
- Credo strict mode enforced
- Dialyzer from day one
- Two esbuild/tailwind targets: `blackboex_web` and `blackboex_admin`
- `use Blackboex.Schema` — use for ALL domain schemas (not `use Ecto.Schema` directly). Provides: `use Ecto.Schema`, `import Ecto.Changeset`, and `@primary_key false` (suitable for embedded/DTO schemas). Never use `use Ecto.Schema` directly in the domain app.

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
- Context facade: `Blackboex.Apis` (singular namespace)
- Sub-context: `Blackboex.Apis.Files`, `Blackboex.Apis.Versions`
- Query module: `Blackboex.Apis.FileQueries`, `Blackboex.Apis.VersionQueries`
- Schema: `Blackboex.Apis.Api`, `Blackboex.Apis.ApiFile` (singular)
- Worker: stays at current path, never rename (Oban jobs reference module name)

### Security
- `Blackboex.LLM.SecurityConfig` is the SINGLE source for allowed/prohibited modules
- Never duplicate these lists. Always reference `SecurityConfig`

## Test Standards — Mandatory Rules

### Fixture-First Policy

Every schema that needs to be inserted in a test MUST use a fixture function — never create entities inline with `%Schema{} |> changeset |> Repo.insert`. The only exception is changeset validation tests that test the changeset itself without inserting.

**Fixture modules** (all auto-imported via `DataCase` and `ConnCase`):

| Module | Functions | Schemas |
|--------|-----------|---------|
| `AccountsFixtures` | `user_fixture/1`, `unconfirmed_user_fixture/1`, `user_scope_fixture/0,1` | User |
| `OrganizationsFixtures` | `org_fixture/1`, `user_and_org_fixture/1`, `org_member_fixture/1`, `create_user_and_org/1`, `create_org/1` | Organization, Membership |
| `ProjectsFixtures` | `project_fixture/1`, `project_membership_fixture/1`, `create_project/1` | Project, ProjectMembership |
| `ApisFixtures` | `api_fixture/1`, `api_key_fixture/2`, `invocation_log_fixture/1`, `metric_rollup_fixture/1`, `create_api/1`, `create_org_and_api/1` | Api, ApiKey, InvocationLog, MetricRollup |
| `ApiFilesFixtures` | `api_file_fixture/1`, `default_files_fixture/2`, `latest_revision/1` | ApiFile, ApiFileRevision |
| `BillingFixtures` | `subscription_fixture/1`, `daily_usage_fixture/1`, `usage_event_fixture/1` | Subscription, DailyUsage, UsageEvent |
| `ConversationsFixtures` | `conversation_fixture/3`, `run_fixture/1` | Conversation, Run |
| `FlowsFixtures` | `flow_fixture/1`, `flow_from_template_fixture/1`, `create_flow/1`, `create_org_and_flow/1` | Flow |
| `FlowExecutionsFixtures` | `flow_execution_fixture/1`, `node_execution_fixture/1` | FlowExecution, NodeExecution |
| `FlowSecretsFixtures` | `flow_secret_fixture/1` | FlowSecret |
| `LlmFixtures` | `llm_usage_fixture/1` | LLM.Usage |
| `PagesFixtures` | `page_fixture/1`, `create_page/1`, `create_page_tree/1` | Page |
| `PlaygroundsFixtures` | `playground_fixture/1`, `create_playground/1` | Playground |
| `PlaygroundExecutionsFixtures` | `execution_fixture/1` | PlaygroundExecution |
| `PlaygroundConversationsFixtures` | `playground_conversation_fixture/1`, `playground_run_fixture/1`, `playground_event_fixture/1` | PlaygroundConversation, PlaygroundRun, PlaygroundEvent |
| `PageConversationsFixtures` | `page_conversation_fixture/1`, `page_run_fixture/1`, `page_event_fixture/1` | PageConversation, PageRun, PageEvent |
| `FlowConversationsFixtures` | `flow_conversation_fixture/1`, `flow_run_fixture/1`, `flow_event_fixture/1` | FlowConversation, FlowRun, FlowEvent |
| `TestingFixtures` | `test_suite_fixture/1` | TestSuite |
| `MockDefaults` | `stub_llm_client/1`, `stub_stripe/1` | — |

### Named Setup Composition

Use composable named setups instead of inline setup blocks:

```elixir
# CORRECT — compose named setups
setup [:register_and_log_in_user, :create_org_and_api]

# WRONG — inline setup block duplicating fixture logic
setup %{user: user} do
  {:ok, %{organization: org}} = Organizations.create_organization(user, %{name: "Test"})
  {:ok, api} = Apis.create_api(%{...})
  %{org: org, api: api}
end
```

Available named setups:
- `:register_and_log_in_user` — creates user, logs in, returns `%{conn, user, scope}`
- `:create_user_and_org` — creates user + org, returns `%{user, org}`
- `:create_org` — creates org for existing user in context, returns `%{org}`
- `:create_api` — creates API for existing user + org, returns `%{api}`
- `:create_org_and_api` — creates org + API for existing user, returns `%{org, api}`
- `:create_project` — creates project for existing user + org, returns `%{project}`; if only user in context, also creates org and returns `%{org, project}`
- `:create_flow` — creates flow for existing user + org, returns `%{flow}`
- `:create_org_and_flow` — creates org + flow for existing user, returns `%{org, flow}`
- `:create_page` — creates page for existing user + org (optionally uses `:project` from context), returns `%{page}`
- `:create_page_tree` — creates root + 2 children + 1 grandchild pages for existing user + org + project, returns `%{root_page, child_1, child_2, grandchild}`
- `:create_playground` — creates playground for existing user + org (optionally uses `:project` from context), returns `%{playground}`
- `:stub_llm_client` — stubs LLM mock with safe defaults
- `:stub_stripe` — stubs Stripe mock with safe defaults

### Test Structure Rules

1. **No redundant imports** — `DataCase` auto-imports all fixtures, `Mox.verify_on_exit!`, `Ecto` helpers. `ConnCase` auto-imports all of that plus `Phoenix.LiveViewTest` and `LiveViewHelpers`
2. **No `import Mox` for verify only** — `Mox.verify_on_exit!` is automatic in DataCase. Only add `import Mox` if tests use `expect/3` or `stub/3` directly
3. **No `defp` helpers that duplicate fixture logic** — if you need `create_org`, `build_api`, `insert_log`, etc., use the shared fixture. If a fixture doesn't exist for a schema, create one
4. **New schema = new fixture** — when adding a new Ecto schema that will be inserted in tests, create the fixture function in the appropriate `*Fixtures` module BEFORE writing tests
5. **Specific names in setup** — if a test asserts on a specific name/slug, pass it to the fixture (`api_fixture(%{name: "My API"})`) instead of inlining the whole creation
6. **LiveView helpers** — use `assert_has(view, selector)` and `refute_has(view, selector)` from `LiveViewHelpers` instead of raw `has_element?`

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
│   ├── lib/blackboex/testing/AGENTS.md            — TestRunner, validation
│   ├── lib/blackboex/flow_agent/AGENTS.md         — Flow AI agent (NL → JSON)
│   ├── lib/blackboex/flow_conversations/AGENTS.md — Flow chat persistence
│   └── lib/blackboex/audit/AGENTS.md              — ExAudit, AuditLog
├── apps/blackboex_web/AGENTS.md                   — Web: routing, auth flow, plugs
│   ├── lib/blackboex_web/components/AGENTS.md     — FULL component catalog (SaladUI + shared + editor)
│   ├── lib/blackboex_web/live/AGENTS.md           — LiveView patterns + catalog of all views
│   ├── lib/blackboex_web/admin/AGENTS.md          — Backpex admin, 23 LiveResources
│   ├── lib/blackboex_web/plugs/AGENTS.md          — All custom plugs, composition order
│   └── lib/blackboex_web/controllers/AGENTS.md    — Controllers, UserAuth, hooks
```

**Rule:** Before generating code in ANY area, read the relevant AGENTS.md first. The component catalog (`components/AGENTS.md`) is especially critical — all UI must be compositions of existing components.
