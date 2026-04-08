# AGENTS.md — Agent Context

AI code generation orchestration. Entry point: `Blackboex.Agent` facade.

## Architecture

```
Agent.start_generation/3 or Agent.start_edit/3   ← public facade
  └─→ Oban KickoffWorker (queue: generation, max_attempts: 2)
        ├─→ Creates Conversation + Run (Ecto.Multi)
        ├─→ Persists initial user_message Event
        └─→ Starts Agent.Session GenServer
              └─→ Session delegates to Session.* sub-modules
                    └─→ Pipeline.* for code generation phases
```

## Agent Facade (`agent.ex`)

```elixir
Agent.start_generation(Api.t(), trigger_message, user_id) :: {:ok, run_id} | {:error, term()}
Agent.start_edit(Api.t(), instruction, user_id) :: {:ok, run_id} | {:error, term()}
```

Previously on `Blackboex.Apis` — now lives here. All callers must use `Agent`, not `Apis`.

## Pipeline Sub-Modules (`Agent.Pipeline.*`)

`Agent.CodePipeline` is the thin orchestrator. Logic is split by phase:

| Module | Responsibility |
|--------|---------------|
| `Pipeline.Budget` | Token/cost/time guardrail checks |
| `Pipeline.Generation` | LLM calls for code generation and editing |
| `Pipeline.Validation` | compile → lint → test loop, retry logic |
| `Pipeline.CodeParser` | Parse LLM output (SEARCH/REPLACE or full code) |

**Rule:** New pipeline logic goes into the appropriate `Pipeline.*` module, not into `CodePipeline` directly.

## Session Sub-Modules (`Agent.Session.*`)

`Agent.Session` is a thin GenServer shell. Logic is split:

| Module | Responsibility |
|--------|---------------|
| `Session.ChainRunner` | LangChain loop execution, tool dispatch |
| `Session.EventTranslator` | LangChain callbacks → `Conversations.Event` persistence |
| `Session.StreamManager` | Token streaming to PubSub |
| `Session.SchemaRegistration` | Schema extraction and API update after submission |

**Rule:** Keep `Agent.Session` GenServer under 200 lines. Extract new logic to `Session.*`.

## Two Execution Modes

| Mode | Module | LLM Calls | Use When |
|------|--------|-----------|---------|
| Agentic loop | `Agent.Session` | 8-10 | Complex iterative generation |
| Deterministic | `Agent.CodePipeline` | 2-4 | Predictable flow sufficient |

## Tools (Agentic Mode)

`compile_code`, `format_code`, `lint_code`, `generate_tests`, `run_tests`, `submit_code`

## Guardrails

- Max iterations, max cost (cents), max time (wall-clock)
- Loop detection: repeated identical tool calls
- Violation → run marked `:partial` with `error_summary`

## PubSub Topics

- `run:#{run_id}` — real-time event stream for LiveView
- `api:#{api_id}` — API-level status changes

## Key Dependencies

- `CodeGen` — compilation, linting
- `Testing.TestRunner` — test execution (30s timeout, 20MB heap)
- `Docs.DocGenerator` — documentation generation
- `LLM.CircuitBreaker` — health check before LLM calls
- `Conversations` — event/run persistence

## Gotchas

1. **Task.async_nolink for LLM calls** — Session survives LLM failures. Handle `{:DOWN, ref, ...}`.
2. **Circuit breaker caller responsibility** — call `CircuitBreaker.allow?/1` before, `record_success/failure` after every LLM call.
3. **Recovery worker** — `RecoveryWorker` runs every 2 min, marks runs stale >120s as `:failed`.
4. **Concurrent runs** — `KickoffWorker` has `unique: [period: 30]` to prevent duplicate runs for same API.
5. **`touch_run/1` is liveness signal** — any long-running step must call it or RecoveryWorker fires.
