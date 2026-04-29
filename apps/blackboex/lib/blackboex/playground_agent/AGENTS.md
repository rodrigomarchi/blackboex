# PlaygroundAgent

AI chat agent dedicated to Playgrounds. Generates or edits the single-file Elixir
script of a `Blackboex.Playgrounds.Playground`. Separate pipeline from the API
`Blackboex.Agent` — Playground scripts have a simpler model (single file, no
validation/fix loops), a different sandbox (`Blackboex.Playgrounds.Executor`),
and dedicated prompts teaching the model about that sandbox.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.PlaygroundAgent` | Facade — `start/3` picks `:generate` vs `:edit` from `playground.code`, enqueues `KickoffWorker`. |
| `PlaygroundAgent.KickoffWorker` | Oban worker on queue `:playground_agent`, `max_attempts: 1`, `unique: [keys: [:playground_id], period: 30]`. Creates conversation + run + initial user-message event, broadcasts `:run_started`, starts `Session`. |
| `PlaygroundAgent.Session` | GenServer — CircuitBreaker check → `Task.Supervisor.async_nolink` on `Blackboex.SandboxTaskSupervisor` → 3-minute timeout. Monitored via Registry `PlaygroundAgent.SessionRegistry`. |
| `PlaygroundAgent.ChainRunner` | Runs the pipeline in the task; on success calls `Playgrounds.record_ai_edit` to apply the edit atomically and broadcasts `:run_completed`; on failure marks run failed and broadcasts `:run_failed`. |
| `PlaygroundAgent.CodePipeline` | Single LLM call via `Blackboex.LLM.Config.client()`. No validation/fix loops. Streams when a `token_callback` is provided. Extracts code via `CodeParser`. |
| `PlaygroundAgent.CodeParser` | Extracts the first ```` ```elixir/```ex/``` ```` fence; picks up an optional `Resumo:` line for `summary`. |
| `PlaygroundAgent.StreamManager` | Buffers LLM tokens in the process dictionary; flushes on 20+ chars or `\n` as `{:code_delta, %{delta, run_id}}` broadcasts. Also exposes `broadcast_run/2`, `broadcast_playground/2`. |
| `PlaygroundAgent.Prompts` | Dedicated system prompts (`:generate` and `:edit`) teaching the model about the Playground sandbox: allowlist (Enum/Map/List/…/Jason), helpers (`Blackboex.Playgrounds.Http`, `…Api`), style (PT comments, `IO.puts`, pipe operator, `{:ok, _} \| {:error, _}` handling), forbidden constructs (`defmodule`, `Function.capture`, `File`, `System`, `:erlang`). |

## Public API

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `start/3` | `(Playground.t(), scope(), String.t()) :: {:ok, Oban.Job.t()} \| {:error, :empty_message \| term()}` | Enqueued Oban job or error | Picks `generate`/`edit` run type, enqueues `KickoffWorker`; returns `{:error, :empty_message}` if message is blank |

`scope` is `%{user: %{id: term()}}` — the standard `Blackboex.Accounts.Scope` struct satisfies this.

## PubSub topics

| Topic | Messages |
|-------|----------|
| `"playground_agent:playground:#{playground_id}"` | `{:run_started, %{run_id, run_type, playground_id}}` |
| `"playground_agent:run:#{run_id}"` | `{:code_delta, %{delta, run_id}}`, `{:run_completed, %{code, summary, run_id, run: Run.t()}}`, `{:run_failed, %{reason, run_id}}` |

`PlaygroundLive.Edit` subscribes to the playground topic in `mount` and to the run topic
when it receives `:run_started`.

## Supervision tree

In `Blackboex.Application`, alongside `Blackboex.Agent.*`:

```elixir
{Registry, keys: :unique, name: Blackboex.PlaygroundAgent.SessionRegistry},
{DynamicSupervisor, name: Blackboex.PlaygroundAgent.SessionSupervisor, strategy: :one_for_one}
```

Tasks run under the shared `Blackboex.SandboxTaskSupervisor`.

## Prompt response contract

The LLM must respond with exactly one fenced Elixir block; everything outside the
fence is ignored for code extraction, but a `Resumo: ...` line (if present) becomes
the run's `run_summary`. Failing to emit a code fence yields an error
`"resposta do modelo não continha bloco de código Elixir"` and marks the run failed.

## Budgeting and safety

- Session timeout: **3 minutes** (vs 7 min for the API pipeline — single LLM call is fast).
- Unique-job constraint on `playground_id` for 30s prevents double-click spam.
- `CircuitBreaker.allow?(:anthropic)` gates chain execution; on open, run fails with a
  user-friendly message.

## Applying the edit

`ChainRunner.handle_chain_success/2` calls `Blackboex.Playgrounds.record_ai_edit/3`, which
atomically:
1. Creates a `PlaygroundExecution` with `status: "ai_snapshot"` and `code_snapshot: code_before`
   (so the history sidebar can revert the AI's edit by selecting the prior snapshot).
2. Updates `playground.code` to the new code.

## Tests

- `Blackboex.PlaygroundAgent.*Test` — unit tests per module.
- `Blackboex.PlaygroundAgentIntegrationTest` (`@moduletag :integration`) — smoke test running
  `ChainRunner.run_chain` end-to-end with a `Mox`-stubbed `Blackboex.LLM.ClientMock`.
