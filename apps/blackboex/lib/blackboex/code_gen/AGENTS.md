# AGENTS.md — CodeGen Context

Compilation, validation, and security enforcement for user-generated API code.

Facade: `Blackboex.CodeGen` (`code_gen.ex`). All callers use the facade.

## Pipeline Overview

```
Source code
  ├─→ AstValidator — security checks (forbidden modules, dangerous fns, atom limit)
  ├─→ Compiler — wraps in namespace, Module.create/3, hot reload
  ├─→ Linter — Credo + auto-format
  └─→ SchemaExtractor — param/response JSON schema from @spec
```

## Key Modules

| Module | Purpose | File |
|--------|---------|------|
| `CodeGen` | Facade: `compile/2`, `unload/1`, `validate_and_test/3` | `code_gen.ex` |
| `Compiler` | `compile/2`, `compile_files/2`, `unload/1`, `module_name_for/1` | `compiler.ex` |
| `AstValidator` | Security validation on parsed AST | `ast_validator.ex` |
| `Linter` | Credo + auto-format | `linter.ex` |
| `DiffEngine` | `compute_diff/2`, `apply_search_replace/2` | `diff_engine.ex` |
| `SchemaExtractor` | Extract param/response JSON schemas | `schema_extractor.ex` |
| `ModuleBuilder` | Wraps handler code in proper module structure | `module_builder.ex` |
| `Sandbox` | Isolated execution environment | `sandbox.ex` |

**Note:** `DiffEngine` moved here from `Apis` context. Use `CodeGen.DiffEngine`, not `Apis.DiffEngine`.

## Security Rules

- **Handler style enforced:** Pure functions returning maps. No Plug.Conn manipulation.
- **No forbidden modules:** System, File, Port, :os, :erlang (subset), Code, Process (subset)
- **No network access:** No :httpc, :hackney, Req, HTTPoison
- **No code generation:** No Code.compile_string, Code.eval_string, apply/3 with dynamic module
- **SecurityConfig is the source:** `LLM.SecurityConfig` owns the lists — AstValidator reads from it. Never duplicate.

## Runtime Env Vars (`conn.assigns.env`)

Compiled API Handler code may read project-scoped env vars from
`conn.assigns.env`. The runtime map is populated by
`BlackboexWeb.Plugs.DynamicApiRouter` via
`Blackboex.ProjectEnvVars.load_runtime_map(api.project_id)` *before* the
module is invoked in the sandbox.

Contract:

```elixir
def handle(params) do
  # NOT: System.get_env("FOO") — SecurityViolation
  # OK:
  api_key = conn.assigns.env["MY_KEY"]
  # ...
end
```

`System.get_env/1`, `:os.getenv/1`, and `Application.get_env/2` are all blocked
by `LLM.SecurityConfig`. `conn.assigns.env` is the only way to read env vars
from Handler code.

## Sandbox Constraints

| Limit | Default | Hard Cap |
|-------|---------|----------|
| Timeout | 30s | 60s |
| Heap size | 20MB | 50MB |
| Atom count | 500 | — |

## Gotchas

1. **Module.create/3 persists until purge** — always call `Compiler.unload/1` before recompiling same module.
2. **Dynamic modules lost on restart** — Registry reloads from DB on init. Never clear `source_code` on a published API.
3. **Billing gate** — `Agent.CodePipeline` checks `Billing.Enforcement` before LLM generation calls.
4. **ExUnit module leak** — use `SandboxCase` instead of `use ExUnit.Case` in generated tests.
