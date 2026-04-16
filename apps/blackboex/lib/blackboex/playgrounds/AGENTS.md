# Playgrounds Context

Interactive single-cell Elixir REPL within projects for code experimentation.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.Playgrounds` | Facade — CRUD operations, `execute_code/2`, `change_playground/2` |
| `Blackboex.Playgrounds.Playground` | Schema — name, slug, code (text), last_output, description, project_id, organization_id, user_id |
| `Blackboex.Playgrounds.PlaygroundQueries` | Query builders — `list_for_project/1`, `by_project_and_slug/2`, `search/2` |
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

## Fixtures

`Blackboex.PlaygroundsFixtures.playground_fixture/1` — auto-imported via DataCase/ConnCase.
Named setup: `create_playground/1` (requires `:user` + `:org` in context).
