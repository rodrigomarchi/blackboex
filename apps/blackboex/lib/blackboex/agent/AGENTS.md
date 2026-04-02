# AGENTS.md — Agent Pipeline

AI code generation orchestration. Two execution modes: agentic (Session) and deterministic (CodePipeline).

## Architecture Overview

```
User message
  │
  ├─→ Apis.start_agent_generation/3 or start_agent_edit/3
  │     │
  │     └─→ Oban KickoffWorker (queue: generation, max_attempts: 2)
  │           │
  │           ├─→ Creates Conversation + Run in DB (Ecto.Multi)
  │           ├─→ Persists initial user_message Event
  │           └─→ Starts Agent.Session GenServer
  │
  └─→ Session GenServer
        │
        ├─→ Builds LangChain LLMChain with tools + callbacks
        ├─→ Runs chain via Task.async_nolink (non-blocking)
        ├─→ LangChain callbacks persist Events + broadcast PubSub
        ├─→ Guardrails checked after each tool execution
        └─→ On submit_code: saves results, creates ApiVersion, updates Api
```

## Two Execution Modes

### 1. Agent.Session (Agentic Loop)
- LangChain-based with 6 tools, LLM decides next action
- 8-10 LLM calls per run
- Full autonomy: LLM chooses when to compile, test, fix
- Used for complex generation requiring iterative refinement

### 2. Agent.CodePipeline (Deterministic)
- Fixed pipeline: generate → format → compile → lint → test → docs
- 2-4 LLM calls (LLM only for generation + fixes)
- Retry loops: max 2 retries per stage on failure
- Max 8 total LLM calls per pipeline run
- Used when predictable flow is sufficient

## Tools (Session Mode)

| Tool | Purpose | Event Type |
|------|---------|------------|
| `compile_code` | Compile via CodeGen.Compiler | tool_call/tool_result |
| `format_code` | Auto-format via Linter | tool_call/tool_result |
| `lint_code` | Credo analysis via Linter | tool_call/tool_result |
| `generate_tests` | LLM-based test generation | tool_call/tool_result |
| `run_tests` | Isolated test execution via TestRunner | tool_call/tool_result |
| `submit_code` | Final submission (saves + creates version) | tool_call/tool_result |

## Guardrails

- **Max iterations:** Configurable per run (prevents infinite loops)
- **Max cost:** Token cost ceiling in cents
- **Max time:** Wall-clock timeout (KickoffWorker: 7 min)
- **Loop detection:** Detects repeated identical tool calls
- Violation → run marked as `:partial` with error_summary

## Event Sourcing

Every action persists as a `Conversations.Event`:
- Types: `user_message`, `system_message`, `assistant_message`, `tool_call`, `tool_result`, `code_snapshot`, `guardrail_trigger`, `error`, `status_change`
- Events have sequence numbers for ordering
- Token usage tracked per event (input_tokens, output_tokens, cost_cents)

## PubSub Topics

- `run:#{run_id}` — real-time event stream for LiveView
- `api:#{api_id}` — API-level updates (status changes, new versions)

## Key Dependencies

- `CodeGen.Compiler` — compilation
- `CodeGen.Linter` — formatting/linting
- `Testing.TestGenerator` — test generation
- `Testing.TestRunner` — test execution (30s timeout, 20MB heap)
- `Docs.DocGenerator` — documentation generation
- `LLM.CircuitBreaker` — health check before LLM calls
- `Conversations` — event/run persistence

## Gotchas

1. **Task.async_nolink for LLM calls** — Session uses non-linked tasks so GenServer survives LLM failures. Must handle `{:DOWN, ref, ...}` for crash resilience.
2. **Circuit breaker check first** — Always call `CircuitBreaker.allow?/1` before LLM request. Record success/failure after.
3. **Token accumulation** — Track cumulative tokens across all events in a run. Pipeline accumulates via `LLM.Usage` struct.
4. **Recovery worker** — `RecoveryWorker` runs every 2 min, finds runs stale >120s, marks as `:failed`. Don't rely on Session cleanup alone.
5. **Concurrent runs** — KickoffWorker has `unique: [period: 30]` to prevent duplicate runs for same API.
6. **Module registration after submit** — On `submit_code`, Session calls `Compiler.compile/2` then `Registry` update. Both must succeed or the version is saved but not deployed.
