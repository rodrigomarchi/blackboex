# AGENTS.md — CodeGen Pipeline

Compilation, validation, and security enforcement for user-generated API code.

## Pipeline Overview

```
Source code (string)
  │
  ├─→ AstValidator — security checks on AST
  │     • No forbidden modules (System, File, Port, :os, etc.)
  │     • No dangerous functions (send, spawn, apply with dynamic module)
  │     • Atom count limit (500 max)
  │     • Allowed DTOs: Request, Response, Params only
  │
  ├─→ Compiler — compilation to live module
  │     • Validates handler style (no json(), put_status(), send_resp(), conn refs)
  │     • Wraps in namespace: Blackboex.Apis.Compiled.Api_<uuid>
  │     • Module.create/3 for dynamic compilation
  │     • Hot reload: :code.purge + :code.delete before recompile
  │
  ├─→ Linter — code quality
  │     • Credo analysis via Linter.run_all/1
  │     • Auto-format via Linter.auto_format/1
  │
  └─→ SchemaExtractor — param/response schema from code
        • Extracts @spec return types
        • Builds JSON Schema for param validation
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `Compiler` | `compile/2` → `{:ok, module}`, `unload/1`, `module_name_for/1` |
| `UnifiedPipeline` | `validate_and_test/3`, `validate_on_save/4`, `run_for_edit/5` |
| `AstValidator` | Security validation on parsed AST |
| `Linter` | Credo + auto-format |
| `SchemaExtractor` | Extract param/response JSON schemas |
| `ModuleBuilder` | Wraps handler code in proper module structure |
| `Sandbox` | Isolated execution environment |

## UnifiedPipeline Stages

1. **validate_and_test/3** — Full pipeline for new code: compile → lint → AST validate → extract schema → generate tests → run tests
2. **validate_on_save/4** — Quick validation on editor save: compile → lint (no tests)
3. **run_for_edit/5** — LLM edit + validation: generate edit → compile → lint → test
4. **generate_edit_only/5** — LLM edit without validation (for preview)

## Sandbox Constraints

| Limit | Value | Hard Cap |
|-------|-------|----------|
| Timeout | 30s default | 60s max |
| Heap size | 20MB default | 50MB max |
| Atom count | 500 max | — |

## Security Rules

- **Handler style enforced:** Code must be pure functions returning maps. No Plug.Conn manipulation.
- **No forbidden modules:** System, File, Port, :os, :erlang (subset), Code, Process (subset)
- **No network access:** No :httpc, :hackney, Req, HTTPoison
- **No code generation:** No Code.compile_string, Code.eval_string, apply/3 with dynamic module
- **AST-level validation:** Runs BEFORE compilation to prevent side effects during compile

## Gotchas

1. **ExUnit module leak** — `Code.compile_string` with `use ExUnit.Case` auto-registers modules with ExUnit.Server. Use `SandboxCase` instead.
2. **Module.create/3 persists until purge** — Always call `Compiler.unload/1` before recompiling same module.
3. **:code.purge is destructive** — Kills all processes using old module version. Safe only because each API gets unique module name.
4. **Dynamic modules lost on restart** — Registry reloads from DB on init. `DynamicApiRouter` has compile-from-DB fallback.
5. **Billing gate** — `CodeGen.Pipeline` checks `Billing.Enforcement` before LLM generation calls. Bypass = free tier abuse.
6. **Credo cyclomatic complexity** — Max 9. Extract complex cond/case into function clauses to stay under limit.
