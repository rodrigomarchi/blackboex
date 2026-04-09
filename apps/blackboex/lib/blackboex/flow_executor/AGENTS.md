# AGENTS.md — Flow Executor

The flow executor parses, validates, builds, and runs BlackboexFlow definitions using the Reactor library.

## Architecture

```
FlowExecutor (facade)
  ├── BlackboexFlow        — Validates canonical JSON format (9 node types)
  ├── DefinitionParser     — Parses JSON into ParsedFlow/ParsedNode structs
  ├── CodeValidator         — AST-level validation of Elixir code in nodes
  ├── SecretResolver       — Replaces {{secrets.X}} placeholders
  ├── ReactorBuilder       — Builds Reactor DAG from ParsedFlow
  │   └── Collector        — Picks first non-skipped result from multiple end nodes
  ├── ExecutionMiddleware  — Persists NodeExecution records, shared_state, PubSub
  └── Nodes/               — Reactor.Step implementations (one per node type)
```

## Node Types (9)

| Type | Module | File | Inputs | Outputs | Key Features |
|------|--------|------|--------|---------|-------------|
| `start` | `Nodes.Start` | `nodes/start.ex` | 0 | 1 | Payload validation, state initialization |
| `elixir_code` | `Nodes.ElixirCode` | `nodes/elixir_code.ex` | 1 | 1 | Code.eval_string, compensate/backoff |
| `condition` | `Nodes.Condition` | `nodes/condition.ex` | 1 | N | Branch index routing, compensate/backoff |
| `end` | `Nodes.EndNode` | `nodes/end_node.ex` | 1 | 0 | Response mapping, schema validation |
| `http_request` | `Nodes.HttpRequest` | `nodes/http_request.ex` | 1 | 1 | Req client, interpolation, 4 auth modes, retry |
| `delay` | `Nodes.Delay` | `nodes/delay.ex` | 1 | 1 | Process.sleep, 3-layer safety cap |
| `sub_flow` | `Nodes.SubFlow` | `nodes/sub_flow.ex` | 1 | 1 | Nested flow execution, depth limit (5), IDOR-safe |
| `for_each` | `Nodes.ForEach` | `nodes/for_each.ex` | 1 | 1 | Task.async_stream, batching, accumulator |
| `webhook_wait` | `Nodes.WebhookWait` | `nodes/webhook_wait.ex` | 1 | 1 | Halts reactor, sets execution to "halted" |

## Shared Infrastructure

| Module | Purpose | File |
|--------|---------|------|
| `Nodes.Helpers` | `extract_input_and_state`, `execute_with_timeout`, `wrap_output` | `nodes/helpers.ex` |
| `Nodes.BranchGate` | Wraps condition-reachable nodes, handles `__branch_skipped__` sentinel | `nodes/branch_gate.ex` |

## Branch Gating

Condition nodes output `%{branch: index, value: input, state: state}`. Downstream nodes are wrapped in `BranchGate` which checks for the `__branch_skipped__` sentinel. Non-matching branches get early return. The `Collector` step picks the first non-skipped result from multiple end nodes.

## Async Execution

- `config :blackboex, :flow_executor_async, false` in test.exs (Ecto sandbox safety)
- Production default: `true` — steps run in parallel where the DAG allows
- Start node and Collector always run synchronously

## Halt/Resume (webhook_wait)

- `webhook_wait` returns `{:halt, info}` — Reactor halts, FlowExecutor returns `{:halted, _}`
- Execution status set to `"halted"` in DB before halt
- Migration: `halted_state` (binary) + `wait_event_type` (string) columns on `flow_executions`

## Key Invariants

- **Shared state**: Atomic jsonb merge via `COALESCE(shared_state, '{}'::jsonb) || ?::jsonb`
- **Node limit**: Max 100 nodes, 500 edges per flow
- **Atom safety**: Node IDs match `/^n\d+$/`, item_variable validated with regex + length cap
- **Sub-flow depth**: Max 5 levels, tracked via process dictionary
- **Code sandboxing**: All user code runs through `CodeValidator` AST checks before execution

## Test Files

| Test | Coverage |
|------|----------|
| `blackboex_flow_test.exs` | Validation for all 9 types |
| `definition_parser_test.exs` | Parsing, cycles, orphans |
| `code_validator_test.exs` | AST validation |
| `reactor_builder_test.exs` | DAG construction, branching |
| `execution_middleware_test.exs` | NodeExecution persistence, state merge |
| `e2e_test.exs` | Linear + branching flows |
| `template_e2e_test.exs` | Hello World template full pipeline |
| `all_nodes_e2e_test.exs` | All 9 types, both branches |
| `nodes/*_test.exs` | Unit tests per node type |
