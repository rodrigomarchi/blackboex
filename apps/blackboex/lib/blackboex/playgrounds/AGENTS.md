# Playgrounds Context

Interactive single-cell Elixir REPL within projects for code experimentation.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.Playgrounds` | Facade — CRUD operations, `execute_code/2`, `change_playground/2` |
| `Blackboex.Playgrounds.Playground` | Schema — name, slug, code (text), last_output, description, project_id, organization_id, user_id |
| `Blackboex.Playgrounds.PlaygroundQueries` | Query builders — `list_for_project/1`, `by_project_and_slug/2`, `search/2` |
| `Blackboex.Playgrounds.Executor` | Sandboxed code execution with allowlist security |

## Executor Security

- **AST validation** via `CodeGen.ASTValidator.validate/1` (reused, no API coupling)
- **Allowlist approach**: Only safe modules permitted (Enum, Map, List, String, etc.)
- **Blocked**: `defmodule`, `Function.capture`, dynamic atom module refs (`:"Elixir.*"`), Erlang module calls
- **Process isolation**: `Task.Supervisor.async_nolink` on `SandboxTaskSupervisor` with `max_heap_size` (10MB) + timeout (5s)
- **Rate limiting**: 10 executions/min/user via ExRated
- **Output truncation**: Max 64KB

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
