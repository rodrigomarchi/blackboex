# Workers — Oban background job workers

## Overview

`Blackboex.Workers` contains Oban worker modules for background job processing. Workers are thin shells — they load records, delegate to domain contexts or executors, and handle error cases. They must never be renamed (Oban persists module names in the `oban_jobs` table).

## Workers

### `Blackboex.Workers.FlowExecutionWorker` (`lib/blackboex/workers/flow_execution_worker.ex`)

Runs a flow execution asynchronously after it has been created and enqueued.

| Attribute | Value |
|-----------|-------|
| Queue | `:flows` |
| Max attempts | `3` |
| Args | `%{"execution_id" => uuid, "flow_id" => uuid}` |

**What it does:**
1. Loads the `FlowExecution` record via `FlowExecutions.get_execution/1`
2. Loads the `Flow` record via `Repo.get/2`
3. If the execution is already `completed` or `failed`, returns `:ok` (idempotent on retry)
4. Otherwise calls `FlowExecutor.run(flow, input, execution_id)`
5. On success: calls `FlowExecutions.complete_execution/3` with extracted output and computed duration
6. On error: calls `FlowExecutions.fail_execution/2` with the error message

**Error handling:**
- If the execution record is not found: logs an error, returns `{:error, "execution not found"}`
- If the flow record is not found: marks the execution as failed, returns `{:error, "flow not found"}`
- Retried up to 3 times by Oban on `{:error, _}` returns

**Duration computation:** Uses `started_at` (datetime set by middleware) if present, falls back to `inserted_at`, falls back to `0`.

## How to Enqueue

```elixir
# Enqueue a flow execution job
%{"execution_id" => execution.id, "flow_id" => flow.id}
|> Blackboex.Workers.FlowExecutionWorker.new()
|> Oban.insert()
```

## Invariants

- Workers are **thin shells** — all business logic lives in domain contexts (`FlowExecutions`, `FlowExecutor`)
- Worker module names must **never be renamed** — Oban persists the module atom in the database
- Workers must be idempotent — `FlowExecutionWorker` skips already-terminal executions on retry
- Use `Oban.Testing.assert_enqueued/2` in tests — never call `perform/1` directly in integration tests
- All new workers must be added to this AGENTS.md

## Adding a New Worker

1. Create `lib/blackboex/workers/my_worker.ex` using `use Oban.Worker, queue: :queue_name`
2. Implement `perform/1` with pattern-matched args
3. Add the worker to the Oban config in `config/config.exs` if using a new queue
4. Add the fixture/enqueue pattern to the relevant `*_fixtures.ex` if tests need it
5. Document it in this file
