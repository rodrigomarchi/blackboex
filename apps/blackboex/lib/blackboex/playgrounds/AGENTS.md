# Playgrounds Context

Interactive single-cell Elixir REPL within projects for code experimentation.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.Playgrounds` | Facade — CRUD operations, `execute_code/2`, `change_playground/2` |
| `Blackboex.Playgrounds.Playground` | Schema — name, slug, code (text), last_output, description, project_id, organization_id, user_id |
| `Blackboex.Playgrounds.PlaygroundQueries` | Query builders — `list_for_project/1`, `by_project_and_slug/2`, `search/2` |
| `Blackboex.Playgrounds.Executor` | Sandboxed code execution with allowlist security, IO capture via StringIO |
| `Blackboex.Playgrounds.Completer` | Code completion engine — module introspection via `__info__/1` for allowed modules |

## Executor Security

- **Own AST parsing** with safe atom encoder (max 1000 atoms) — NOT using `CodeGen.ASTValidator` (which blocks IO)
- **Allowlist approach**: Only safe modules permitted (Enum, Map, List, String, IO, etc.) — `Executor.allowed_modules/0`
- **Blocked**: `defmodule`, `Function.capture`, dynamic atom module refs (`:"Elixir.*"`), Erlang module calls
- **Process isolation**: `Task.Supervisor.async_nolink` on `SandboxTaskSupervisor` with `max_heap_size` (10MB) + timeout (5s)
- **IO capture**: `StringIO` + `Process.group_leader/2` captures `IO.puts`/`IO.inspect` output, combined with result
- **Rate limiting**: 10 executions/min/user via ExRated
- **Output truncation**: Max 64KB

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
