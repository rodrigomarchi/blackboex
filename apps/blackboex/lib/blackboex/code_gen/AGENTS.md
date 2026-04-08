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
| `UnifiedPipeline` | `validate_and_test/3`, `validate_on_save/4`, `run_for_edit/5` | `unified_pipeline.ex` |
| `AstValidator` | Security validation on parsed AST | `ast_validator.ex` |
| `Linter` | Credo + auto-format | `linter.ex` |
| `DiffEngine` | `compute_diff/2`, `apply_search_replace/2` | `diff_engine.ex` |
| `SchemaExtractor` | Extract param/response JSON schemas | `schema_extractor.ex` |
| `ModuleBuilder` | Wraps handler code in proper module structure | `module_builder.ex` |
| `Sandbox` | Isolated execution environment | `sandbox.ex` |

**Note:** `DiffEngine` moved here from `Apis` context. Use `CodeGen.DiffEngine`, not `Apis.DiffEngine`.

## UnifiedPipeline Stages

1. `validate_and_test/3` — Full: compile → lint → AST validate → extract schema → generate tests → run tests
2. `validate_on_save/4` — Quick: compile → lint (no tests)
3. `run_for_edit/5` — LLM edit + validation: generate edit → compile → lint → test

## Security Rules

- **Handler style enforced:** Pure functions returning maps. No Plug.Conn manipulation.
- **No forbidden modules:** System, File, Port, :os, :erlang (subset), Code, Process (subset)
- **No network access:** No :httpc, :hackney, Req, HTTPoison
- **No code generation:** No Code.compile_string, Code.eval_string, apply/3 with dynamic module
- **SecurityConfig is the source:** `LLM.SecurityConfig` owns the lists — AstValidator reads from it. Never duplicate.

## Sandbox Constraints

| Limit | Default | Hard Cap |
|-------|---------|----------|
| Timeout | 30s | 60s |
| Heap size | 20MB | 50MB |
| Atom count | 500 | — |

## Gotchas

1. **Module.create/3 persists until purge** — always call `Compiler.unload/1` before recompiling same module.
2. **Dynamic modules lost on restart** — Registry reloads from DB on init. Never clear `source_code` on a published API.
3. **Billing gate** — `CodeGen.Pipeline` checks `Billing.Enforcement` before LLM generation calls.
4. **ExUnit module leak** — use `SandboxCase` instead of `use ExUnit.Case` in generated tests.
