# FlowExecutions — Execution records for flow runs

## Overview

`Blackboex.FlowExecutions` tracks every run of a Flow and each of its individual node executions. It is the runtime log: created when a flow is triggered, updated as nodes execute, and finalized when the flow completes, fails, or halts waiting for an external event. The context is a pure data layer — it does not run flows; `Blackboex.FlowExecutor` and `Blackboex.Workers.FlowExecutionWorker` call into it.

## Modules

### `Blackboex.FlowExecutions` (`lib/blackboex/flow_executions.ex`)
Public facade. All callers (workers, LiveViews, HTTP triggers) go through this module only — never import sub-modules directly.

### `Blackboex.FlowExecutions.FlowExecution` (`lib/blackboex/flow_executions/flow_execution.ex`)
Ecto schema representing a single flow run.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `binary_id` | UUID primary key |
| `status` | `string` | State machine value (see below) |
| `input` | `map` | Trigger input payload |
| `output` | `map` | Final output after completion |
| `shared_state` | `map` | Mutable key-value store merged across nodes |
| `error` | `string` | Error message when status is `failed` |
| `halted_state` | `binary` | Serialized state when halted waiting for event |
| `wait_event_type` | `string` | Event type the execution is waiting for (halted only) |
| `started_at` | `utc_datetime_usec` | Set when status transitions to `running` |
| `finished_at` | `utc_datetime_usec` | Set on `completed`, `failed`, or `halted` |
| `duration_ms` | `integer` | Wall-clock milliseconds from start to finish |
| `flow_id` | `binary_id` FK | Parent flow |
| `organization_id` | `binary_id` FK | Owning organization |
| `project_id` | `binary_id` FK | Owning project |

### `Blackboex.FlowExecutions.NodeExecution` (`lib/blackboex/flow_executions/node_execution.ex`)
Ecto schema representing the execution of a single node within a `FlowExecution`.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `binary_id` | UUID primary key |
| `node_id` | `string` | Node identifier from the flow definition |
| `node_type` | `string` | Node type (e.g. `"http"`, `"llm"`, `"code"`) |
| `status` | `string` | State machine value (see below) |
| `input` | `map` | Input passed to the node |
| `output` | `map` | Output produced by the node |
| `error` | `string` | Error message when status is `failed` |
| `started_at` / `finished_at` | `utc_datetime_usec` | Timing fields |
| `duration_ms` | `integer` | Execution time in milliseconds |
| `flow_execution_id` | `binary_id` FK | Parent flow execution |

Unique constraint: `(flow_execution_id, node_id)` — each node runs at most once per execution.

### `Blackboex.FlowExecutions.FlowExecutionQueries` (`lib/blackboex/flow_executions/flow_execution_queries.ex`)
Query builders only — no `Repo` calls, no side effects.

| Function | Description |
|----------|-------------|
| `list_for_flow/1` | All executions for a flow, newest first |
| `by_id/1` | Single execution by ID |
| `by_org_and_id/2` | Single execution scoped to org (prevents IDOR) |
| `with_node_executions/1` | Preloads `node_executions` association |

## Status State Machines

### FlowExecution statuses
```
pending → running → completed
                 → failed
                 → halted   (waiting for external webhook event)
```
`halted` executions store `wait_event_type` and can be resumed via `get_halted_execution_by_token/2`.

### NodeExecution statuses
```
pending → running → completed
                 → failed
                 → skipped
```

## Public API

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `create_execution/2` | `(Flow.t(), map())` | `{:ok, FlowExecution.t()}` | Creates a `pending` execution for the given flow and input |
| `get_execution/1` | `(id)` | `FlowExecution.t() \| nil` | Loads by ID with node_executions preloaded |
| `get_execution_for_org/2` | `(org_id, id)` | `FlowExecution.t() \| nil` | Org-scoped fetch (use this from web layer) |
| `list_executions_for_flow/1` | `(flow_id)` | `[FlowExecution.t()]` | All executions for a flow |
| `update_execution_status/2` | `(execution, status)` | `{:ok, FlowExecution.t()}` | Generic status update; also sets `started_at` when transitioning to `running` |
| `complete_execution/3` | `(execution, output, duration_ms)` | `{:ok, FlowExecution.t()}` | Sets status `completed`, output, `finished_at`, and duration |
| `fail_execution/2` | `(execution, error)` | `{:ok, FlowExecution.t()}` | Sets status `failed` with error message |
| `halt_execution/2` | `(execution, event_type)` | `{:ok, FlowExecution.t()}` | Sets status `halted` and stores `wait_event_type` |
| `get_halted_execution_by_token/2` | `(webhook_token, event_type)` | `FlowExecution.t() \| nil` | Finds the most recent halted execution matching a flow's webhook token |
| `merge_shared_state/2` | `(execution_id, map())` | `:ok` | Atomically merges new key-value pairs into `shared_state` via Postgres JSONB merge |
| `create_node_execution/1` | `(attrs)` | `{:ok, NodeExecution.t()}` | Creates a node execution record |
| `complete_node_execution/3` | `(node_exec, output, duration_ms)` | `{:ok, NodeExecution.t()}` | Marks node completed |
| `skip_node_execution/2` | `(node_exec, duration_ms)` | `{:ok, NodeExecution.t()}` | Marks node skipped |
| `fail_node_execution/2` | `(node_exec, error)` | `{:ok, NodeExecution.t()}` | Marks node failed |

## Invariants

- External callers NEVER import `FlowExecutionQueries` or schema modules directly — always go through `Blackboex.FlowExecutions`
- `get_execution_for_org/2` must be used from web/HTTP layers to prevent IDOR — raw `get_execution/1` is for internal worker use only
- `merge_shared_state/2` uses a Postgres JSONB merge (`||`) — it is non-transactional relative to other execution updates; callers must tolerate last-write-wins semantics
- A `FlowExecution` in `completed` or `failed` status is terminal — `FlowExecutionWorker` skips re-execution on retry for idempotency
- Node executions have a unique constraint on `(flow_execution_id, node_id)` — each node runs at most once per execution instance
