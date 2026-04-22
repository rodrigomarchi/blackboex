# FlowAgent

AI chat agent dedicated to Flows. Generates or edits the canonical JSON
definition (`BlackboexFlow`) of a `Blackboex.Flows.Flow` from natural-language
prompts. Mirrors the shape of `Blackboex.PageAgent` / `Blackboex.PlaygroundAgent`
but outputs **structured JSON** instead of free text — the response is parsed,
auto-layouted, validated, and atomically applied to `flow.definition`.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.FlowAgent` | Facade — `start/3` validates message length, checks org ownership (IDOR), checks `Billing.Enforcement.check_limit(org, :llm_generation)`, picks `:generate` (empty definition) vs `:edit`, enqueues `KickoffWorker`. |
| `FlowAgent.KickoffWorker` | Oban worker on queue `:flow_agent`, `max_attempts: 1`, `unique: [keys: [:flow_id], period: 30]`. Creates conversation + run + initial user-message event, broadcasts `:run_started`, starts `Session`. |
| `FlowAgent.Session` | GenServer — CircuitBreaker check → `Task.Supervisor.async_nolink` on `Blackboex.SandboxTaskSupervisor` → 3-minute timeout. Monitored via `FlowAgent.SessionRegistry`. |
| `FlowAgent.ChainRunner` | Runs the pipeline in the task; on success calls `Flows.record_ai_edit` and broadcasts `:run_completed`; on failure marks run failed and broadcasts `:run_failed`. |
| `FlowAgent.DefinitionPipeline` | Single LLM call via `Blackboex.LLM.Config.client()`. Streams tokens through `StreamManager`, parses via `DefinitionParser`, fills missing positions via `AutoLayout`, validates via `BlackboexFlow.validate`. |
| `FlowAgent.DefinitionParser` | Extracts `~~~json … ~~~` (or `~~~` / ```` ```json ```` fallbacks) from the model response; also picks the optional `Resumo:` line. |
| `FlowAgent.AutoLayout` | BFS from start node, assigns `x = 50 + depth * 200`, spreads siblings vertically `y += 150`. Preserves existing positions; disconnected components stack below. |
| `FlowAgent.StreamManager` | Buffers LLM tokens in the process dictionary; flushes on 20+ chars or `\n` as `{:definition_delta, %{delta, run_id}}` broadcasts. |
| `FlowAgent.Prompts` | System prompts (`:generate` / `:edit`) in Portuguese teaching the canonical schema + the 11 node types. Injects three real templates as few-shot examples via `Prompts.Examples`. |
| `FlowAgent.Prompts.Examples` | Serializes `HelloWorld`, `RestApiCrud`, and `AllNodesDemo` at compile time for inclusion in the system prompt. Compile-time dependency ensures examples always match live templates. |

## Public API

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `start/3` | `(Flow.t(), scope(), String.t()) :: {:ok, Oban.Job.t()} \| {:error, :empty_message \| :message_too_long \| :forbidden \| :limit_exceeded \| term()}` | Enqueued Oban job or error | Validates input, authorizes, picks run type, enqueues `KickoffWorker` |

`scope` is `%{user: %{id: term()}, organization: %{id: term()}}` — the standard
`Blackboex.Accounts.Scope` struct satisfies this.

## PubSub topics

| Topic | Messages |
|-------|----------|
| `"flow_agent:flow:#{flow_id}"` | `{:run_started, %{run_id, run_type, flow_id}}`, re-broadcast of `:run_completed` and `:run_failed` |
| `"flow_agent:run:#{run_id}"` | `{:definition_delta, %{delta, run_id}}`, `{:run_completed, %{definition, summary, run_id, run}}`, `{:run_failed, %{reason, run_id}}` |

`FlowLive.Edit` subscribes to the flow topic in `mount` and to the run topic
when it receives `:run_started`. On `:run_completed` it pushes
`flow_chat:reload_definition` so the Drawflow JS hook re-imports the graph.

## Supervision tree

In `Blackboex.Application`, alongside the other agent registries:

```elixir
{Registry, keys: :unique, name: Blackboex.FlowAgent.SessionRegistry},
{DynamicSupervisor,
 name: Blackboex.FlowAgent.SessionSupervisor, strategy: :one_for_one, max_children: 100}
```

Tasks run under the shared `Blackboex.SandboxTaskSupervisor`.

## Prompt response contract

The LLM must respond with exactly one `~~~json { ... } ~~~` block (tildes
avoid colliding with JSON strings that contain backticks). Everything outside
is ignored for extraction but a `Resumo:` line (if present) becomes the run's
`run_summary`. Failing to emit valid JSON yields:

- `:no_json_block` — no fence found
- `{:invalid_json, reason}` — fence present but not valid JSON
- `{:invalid_flow, reason}` — valid JSON but fails `BlackboexFlow.validate`

All three mark the run as failed.

## Budgeting and safety

- `Billing.Enforcement.check_limit(org, :llm_generation)` is checked in the
  facade. Rejections surface as `{:error, :limit_exceeded}`.
- IDOR check in `start/3`: `flow.organization_id` must equal `scope.organization.id`.
- `message` trimmed to max 10_000 chars.
- Session timeout: **3 minutes**.
- Unique-job constraint on `flow_id` for 30s prevents double-click spam.
- `CircuitBreaker.allow?(:anthropic)` gates chain execution; on open, run fails.
- User-supplied messages have leading `~~~` / ```` ``` ```` sequences neutralized
  (zero-width space) in `Prompts.user_message/4` to prevent fence-escape injection.

## Applying the edit

`ChainRunner.handle_chain_success/2` calls `Blackboex.Flows.record_ai_edit/3`,
which:
1. Validates the flow belongs to the scope's organization (defense-in-depth IDOR).
2. Updates `flow.definition` via `update_definition/2` (which re-runs `BlackboexFlow.validate`).

The `BlackboexWeb.FlowLive.Edit` LiveView updates its `flow` assign on
`:run_completed` and pushes `flow_chat:reload_definition` so the Drawflow
hook re-imports the graph onto the canvas.

## Tests

- `Blackboex.FlowAgent.*Test` — unit tests per module (`DefinitionParser`,
  `AutoLayout`, `Prompts`, `StreamManager`, `DefinitionPipeline`, `ChainRunner`,
  `Session`, `KickoffWorker`).
- `Blackboex.FlowAgentTest` — facade-level input validation + enqueue.
- `BlackboexWeb.FlowLive.ChatTest` (`@moduletag :liveview`) — chat UI behavior,
  PubSub round-trip, drawer toggle, new-conversation archival.
- Quality gate: `priv/scripts/flow_agent_eval.exs` (manual run against real LLM,
  9/10 threshold on canonical prompts).
