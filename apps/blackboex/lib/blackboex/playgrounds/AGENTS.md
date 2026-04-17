# Playgrounds Context

Interactive single-cell Elixir REPL within projects for code experimentation.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.Playgrounds` | Facade — CRUD, `execute_code/2`, `execute_code_raw/2`, execution history (`create_execution/2`, `complete_execution/4`, `list_executions/1`, `cleanup_old_executions/1`), `record_ai_edit/3` |
| `Blackboex.Playgrounds.Playground` | Schema — name, slug, code (text), last_output, description, project_id, organization_id, user_id; `has_many :executions` |
| `Blackboex.Playgrounds.PlaygroundExecution` | Schema — run_number, code_snapshot, output, status (running/success/error/ai_snapshot), duration_ms, playground_id. `ai_snapshot_changeset/2` accepts empty `code_snapshot` (for first-ever AI edit). |
| `Blackboex.Playgrounds.PlaygroundQueries` | Query builders — `list_for_project/1`, `by_project_and_slug/2`, `search/2` |
| `Blackboex.Playgrounds.ExecutionQueries` | Query builders — `list_for_playground/1` (desc, limit 50), `latest_run_number/1`, `beyond_retention/2` |
| `Blackboex.Playgrounds.Executor` | Sandboxed code execution with allowlist security, IO capture via StringIO |
| `Blackboex.Playgrounds.Http` | Safe HTTP client wrapper — SSRF protection, 5 calls/execution, 3s timeout, 64KB body truncation |
| `Blackboex.Playgrounds.Api` | Convenience wrappers to call project flows (`call_flow/2`) and APIs (`call_api/5`) from playground code |
| `Blackboex.Playgrounds.Completer` | Code completion engine — module introspection via `__info__/1` for allowed modules |

## Executor Security

- **Own AST parsing** with safe atom encoder (max 1000 atoms) — NOT using `CodeGen.ASTValidator` (which blocks IO)
- **Allowlist approach**: Only safe modules permitted (Enum, Map, List, String, IO, Http, Api, etc.) — `Executor.allowed_modules/0`
- **Blocked**: `defmodule`, `Function.capture`, dynamic atom module refs (`:"Elixir.*"`), Erlang module calls
- **Process isolation**: `Task.Supervisor.async_nolink` on `SandboxTaskSupervisor` with `max_heap_size` (10MB) + timeout (15s)
- **IO capture**: `StringIO` + `Process.group_leader/2` captures `IO.puts`/`IO.inspect` output, combined with result
- **Rate limiting**: 10 executions/min/user via ExRated
- **Output truncation**: Max 64KB

## Http Module (SSRF Protection)

- Only allows `GET`, `POST`, `PUT`, `PATCH`, `DELETE` methods
- **Blocked IPs**: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 127.0.0.0/8
- **Exception**: configured base URL host is allowed (for self-calls to project APIs/flows)
- **Per-execution limit**: 5 HTTP calls (tracked via process dictionary)
- **Per-request timeout**: 3 seconds
- **Response body truncation**: 64KB
- **No redirect following** (prevents SSRF via redirect to internal IPs)
- **Config**: `config :blackboex, Blackboex.Playgrounds.Api, base_url: "http://localhost:4000"` — override via `PLAYGROUND_BASE_URL` env var

## Api Module (Flow/API Invocation)

- `Api.call_flow(webhook_token, input)` — POST to `/webhook/:token`, returns parsed JSON
- `Api.call_api(org, project, api, params, api_key)` — POST to `/api/:org/:project/:api` with Bearer auth
- Uses `Http` internally — all SSRF protections, rate limits, and timeouts apply
- Self-calls go through HTTP (not direct context invocation) so all middleware runs (auth, rate limiting, billing)

## Completer

- Uses `Module.__info__(:functions)` + `Module.__info__(:macros)` for introspection
- Filtered against `Executor.allowed_modules/0` — blocked modules return empty results
- Supports module completion (`"Enu"` → `Enum`) and function completion (`"Enum.ma"` → `map/2`)
- NOT using `IEx.Autocomplete` (requires active IEx process)

## Key Patterns

- **Slug**: Auto-generated from name with nanoid hash, immutable after creation
- **Code validation**: Max 256KB (262,144 chars)
- **`last_output` validation**: Max 64KB (65,536 chars)
- **Denormalized `organization_id`**: Follows project-scoped entity convention

## Policy Rules

Defined in `Blackboex.Policy` under `object :playground`:
- `:create` / `:update` — owner, admin, member, project editor
- `:read` — owner, admin, member, project viewer
- `:delete` — owner, admin, project admin
- `:execute` — owner, admin, member, project editor

## Execution History

- Each `Run` press creates a `PlaygroundExecution` with status `"running"` and sequential `run_number`
- On completion, `complete_execution/4` updates output, status, and duration_ms
- Retention: last 50 executions per playground, cleaned via `cleanup_old_executions/1`
- LiveView tracks `executions`, `selected_execution_id`, `selected_execution` assigns
- `execute_code_raw/2` returns raw executor result without persisting (LiveView orchestrates persistence)
- `list_for_playground/1` orders by `desc: inserted_at, desc: run_number` — the `run_number` tiebreak makes ordering deterministic when two rows share the same (second-granularity) timestamp.

## AI Edits

`record_ai_edit(playground, new_code, code_before)` is the transactional hand-off from
`Blackboex.PlaygroundAgent.ChainRunner` into this context. Inside a single `Repo.transaction`
it creates a `PlaygroundExecution` with `status: "ai_snapshot"` and `code_snapshot: code_before`
(so the history sidebar can revert), then updates `playground.code` to `new_code`. Either both
changes land or both roll back. The execution appears in the standard history list alongside
user-run executions — the status badge distinguishes them.

## Public API

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `create_playground/1` | `(map()) :: {:ok, Playground.t()} \| {:error, Ecto.Changeset.t()}` | New playground or changeset error | Inserts a new playground with the given attrs |
| `list_playgrounds/1` | `(Ecto.UUID.t()) :: [Playground.t()]` | List of playgrounds | Lists all playgrounds for a project |
| `list_playgrounds/2` | `(Ecto.UUID.t(), keyword()) :: [Playground.t()]` | List of playgrounds | Lists playgrounds with optional `search:` filter |
| `get_playground/2` | `(Ecto.UUID.t(), Ecto.UUID.t()) :: Playground.t() \| nil` | Playground or nil | Fetches by project_id + playground_id |
| `get_playground_by_slug/2` | `(Ecto.UUID.t(), String.t()) :: Playground.t() \| nil` | Playground or nil | Fetches by project_id + slug |
| `update_playground/2` | `(Playground.t(), map()) :: {:ok, Playground.t()} \| {:error, Ecto.Changeset.t()}` | Updated playground or changeset error | Updates name/description/code fields |
| `delete_playground/1` | `(Playground.t()) :: {:ok, Playground.t()} \| {:error, Ecto.Changeset.t()}` | Deleted playground or changeset error | Deletes a playground record |
| `change_playground/2` | `(Playground.t(), map()) :: Ecto.Changeset.t()` | Changeset | Builds a changeset for form use; `attrs` defaults to `%{}` |
| `execute_code/2` | `(Playground.t(), String.t()) :: {:ok, Playground.t()} \| {:error, String.t()}` | Updated playground or error string | Executes code in sandbox and persists result + code |
| `execute_code_raw/2` | `(Playground.t(), String.t()) :: {:ok, String.t()} \| {:error, String.t()}` | Raw output string or error string | Executes code without persisting; caller handles persistence |
| `create_execution/2` | `(Playground.t(), String.t()) :: {:ok, PlaygroundExecution.t()} \| {:error, Ecto.Changeset.t()}` | New execution record | Creates a `"running"` execution with sequential run_number |
| `complete_execution/4` | `(PlaygroundExecution.t(), String.t(), String.t(), non_neg_integer()) :: {:ok, PlaygroundExecution.t()} \| {:error, Ecto.Changeset.t()}` | Updated execution | Sets output, status, and duration_ms |
| `list_executions/1` | `(Ecto.UUID.t()) :: [PlaygroundExecution.t()]` | List of executions | Returns last 50 executions for a playground, desc order |
| `get_execution/1` | `(Ecto.UUID.t()) :: PlaygroundExecution.t() \| nil` | Execution or nil | Fetches a single execution by id |
| `cleanup_old_executions/1` | `(Ecto.UUID.t()) :: {non_neg_integer(), nil \| [term()]}` | Delete count | Deletes executions beyond the 50-record retention window |
| `record_ai_edit/3` | `(Playground.t(), String.t(), String.t()) :: {:ok, %{playground: Playground.t(), snapshot: PlaygroundExecution.t()}} \| {:error, term()}` | Map with updated playground and snapshot | Atomically saves the AI-generated code and creates a revertable `"ai_snapshot"` execution |

## Executor: Allowed Modules

These are the only modules callable from playground code (`Executor.allowed_modules/0`):

| Category | Modules |
|----------|---------|
| Collections | `Enum`, `Map`, `List`, `MapSet`, `Stream`, `Range`, `Keyword`, `Access` |
| Strings & Atoms | `String`, `Atom`, `Regex`, `URI`, `Base` |
| Numbers | `Integer`, `Float`, `Bitwise` |
| Data structures | `Tuple`, `Inspect` |
| Date/Time | `Date`, `Time`, `DateTime`, `NaiveDateTime`, `Calendar` |
| I/O & formatting | `IO`, `Kernel`, `Jason` |
| Playground helpers | `Blackboex.Playgrounds.Http`, `Blackboex.Playgrounds.Api` |
| Aliased short names | Any suffix of an allowed module (e.g. `Http` after `alias Blackboex.Playgrounds.Http`) |

**Explicitly blocked (will raise at validation time):**
- `defmodule` — prevents polluting the global module namespace
- `Function.capture` — common bypass vector
- Dynamic atom module refs: `:"Elixir.System"`, `:"Elixir.File"`, etc.
- Erlang modules: `:erlang`, `:os`, `:file`, `:io`, `:code`, `:port`, `:process`, `:ets`, `:dets`
- Any module not in the allowlist above (e.g. `System`, `File`, `Process`, `Node`, `Application`)

## Fixtures

`Blackboex.PlaygroundsFixtures.playground_fixture/1` — auto-imported via DataCase/ConnCase.
Named setup: `create_playground/1` (requires `:user` + `:org` in context).

`Blackboex.PlaygroundExecutionsFixtures.execution_fixture/1` — auto-imported via DataCase/ConnCase.
