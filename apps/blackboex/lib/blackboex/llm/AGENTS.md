# AGENTS.md — Blackboex.LLM

AI model interface layer. Provider-agnostic client abstraction, circuit breaking, per-user rate limiting, prompt/template management, streaming token delivery, and usage tracking.

---

## Request Flow

```
1. RateLimiter.check_rate(user_id, plan)          ← reject if over quota
2. CircuitBreaker.allow?(provider)                 ← reject if open
3. client = Config.client()                        ← resolves mock in test
4. client.generate_text(prompt, opts)
     ReqLLMClient → ReqLLM.Context → HTTP to provider
     {:ok, %{content: "...", usage: %{...}}} | {:error, reason}
5. on success: CircuitBreaker.record_success(provider) + LLM.record_usage(attrs)
   on failure: CircuitBreaker.record_failure(provider)
```

For streaming, step 4 is replaced by `StreamHandler.start(self(), prompt, opts)`; LiveView handles `{:llm_token, …}` / `{:llm_done, …}` / `{:llm_error, reason}` messages.

---

## Key Modules

### `Blackboex.LLM.ClientBehaviour`

```elixir
@callback generate_text(prompt :: String.t(), opts :: keyword()) ::
            {:ok, %{content: String.t(), usage: map()}} | {:error, term()}

@callback stream_text(prompt :: String.t(), opts :: keyword()) ::
            {:ok, Enumerable.t()} | {:error, term()}
```

Common opts: `:model` (default `"anthropic:claude-sonnet-4-20250514"`), `:system`, `:user_id` (stripped before HTTP), `:temperature` (default 0.2), `:max_tokens` (default 8192).

### `Blackboex.LLM.ReqLLMClient`

Production implementation. Default model from `Application.get_env(:blackboex, :llm_default_model)`. Never import or call directly — always resolve via `Config.client/0`.

### `Blackboex.LLM.Config`

```elixir
@spec client() :: module()          # returns mock in test, ReqLLMClient in prod
@spec providers() :: [t()]
@spec get_provider(atom()) :: {:ok, t()} | {:error, :unknown_provider}
@spec fallback_models() :: [String.t()]
```

| Atom         | Model string                           | API key env var     |
|--------------|----------------------------------------|---------------------|
| `:anthropic` | `"anthropic:claude-sonnet-4-20250514"` | `ANTHROPIC_API_KEY` |
| `:openai`    | `"openai:gpt-4o"`                      | `OPENAI_API_KEY`    |

### `Blackboex.LLM.CircuitBreaker`

GenServer tracking per-provider health. Registered under its own module name.

#### States and transitions

```
closed ──[5 failures in 60s]──► open
open   ──[30s elapsed]────────► half_open  (lazy: on next allow? call)
half_open ──[2 successes]─────► closed
half_open ──[any failure]─────► open
```

| Constant              | Value  |
|-----------------------|--------|
| `@failure_threshold`  | 5      |
| `@failure_window_ms`  | 60_000 |
| `@recovery_timeout_ms`| 30_000 |
| `@success_threshold`  | 2      |

```elixir
CircuitBreaker.allow?(provider)          # :: boolean()
CircuitBreaker.record_success(provider)  # :: :ok
CircuitBreaker.record_failure(provider)  # :: :ok
CircuitBreaker.get_state(provider)       # :: :closed | :open | :half_open
CircuitBreaker.reset(provider)           # :: :ok  (ops/admin use)
```

The caller is responsible for calling `allow?` before and `record_success/failure` after. The client does not call the circuit breaker automatically.

### `Blackboex.LLM.RateLimiter`

Per-user token bucket via ExRated. Key: `"llm:#{user_id}"`.

```elixir
@spec check_rate(String.t(), atom()) :: :ok | {:error, :rate_limited}
```

| Plan          | Requests / hour |
|---------------|-----------------|
| `:free`       | 10              |
| `:pro`        | 100             |
| `:enterprise` | 1_000           |
| Unknown       | 10              |

### `Blackboex.LLM.Prompts`

All system prompts and generation prompt builders. Do not inline prompt strings in callers.

```elixir
@spec system_prompt() :: String.t()
@spec build_generation_prompt(String.t(), atom()) :: String.t()
@spec allowed_modules() :: [String.t()]
@spec prohibited_modules() :: [String.t()]
```

**Allowed modules:** `Enum`, `Map`, `List`, `String`, `Integer`, `Float`, `Tuple`, `Keyword`, `MapSet`, `Date`, `Time`, `DateTime`, `NaiveDateTime`, `Calendar`, `Regex`, `URI`, `Base`, `Jason`, `Access`, `Stream`, `Range`, `Blackboex.Schema`, Ecto schema/changeset modules.

**Prohibited modules:** `File`, `System`, `IO`, `Code`, `Port`, `Process`, `Node`, `Application`, `:erlang`, `:os`, `Module`, `GenServer`, `Agent`, `Task`, `Supervisor`, `ETS`, `:ets`, `DETS`, `:dets`.

### `Blackboex.LLM.EditPrompts`

SEARCH/REPLACE diff format for conversational code-editing (`Agent.Session`). Conversation history capped at 10 messages.

```elixir
@spec system_prompt() :: String.t()
@spec build_edit_prompt(String.t(), String.t(), [map()]) :: String.t()
@spec parse_response(String.t()) ::
        {:ok, :search_replace, [%{search: String.t(), replace: String.t()}], String.t()}
        | {:ok, :full_code, String.t(), String.t()}
        | {:error, :no_changes_found}
```

`parse_response/1` tries SEARCH/REPLACE blocks first, falls back to full `elixir` code block.

### `Blackboex.LLM.Templates`

```elixir
@spec get(atom()) :: String.t()
```

| Template       | Handler shape                                                    |
|----------------|------------------------------------------------------------------|
| `:computation` | `def handle(params)`                                            |
| `:crud`        | `handle_list/1`, `handle_get/2`, `handle_create/1`, etc.        |
| `:webhook`     | `def handle_webhook(payload)`                                   |

`get/1` has no fallback clause — unknown atom raises `FunctionClauseError`. Validate before calling.

### `Blackboex.LLM.StreamHandler`

```elixir
@spec start(pid(), String.t(), keyword()) :: {:ok, pid()}
```

Spawns a detached `Task` (fire-and-forget via `Task.start/1`). Sends `{:llm_token, token}`, `{:llm_done, full_response}`, or `{:llm_error, reason}` to the caller pid. Always handle `{:llm_error, _}` and set a timeout in `handle_info` — a crashed task never sends `{:llm_done, _}`.

### `Blackboex.LLM.Usage`

Ecto schema for `llm_usage` table. Fields: `provider`, `model`, `input_tokens`, `output_tokens`, `cost_cents`, `operation`, `duration_ms`, `user_id`, `organization_id`, `api_id`. Required: `:provider`, `:model`, `:operation`. Persisted via `Blackboex.LLM.record_usage/1`.

### `Blackboex.LLM.Schemas.GeneratedEndpoint`

Embedded schema for InstructorLite structured output. Fields: `handler_code`, `method`, `description`, `example_request`, `example_response`, `param_schema`. Required: `handler_code`, `method`, `description`.

---

## Testing

Mock: `Blackboex.LLM.ClientMock` via Mox. Config: `config/test.exs` sets `config :blackboex, :llm_client, Blackboex.LLM.ClientMock`. Declaration: `test/support/mocks.ex`.

Use `stub/3` (not `expect/3`) in shared `setup` blocks — Mox stubs are per-process, safe with `async: true`. For streaming tests return a plain `Stream.map/2` enumerable of `{:token, str}` tuples. Tag unit tests `@moduletag :unit`; DB tests use `Blackboex.DataCase`.

---

## Gotchas

**Never call `ReqLLMClient` directly.** Always use `Config.client()`. Direct calls bypass the mock in tests.

**`usage` map may be empty.** `ReqLLMClient` returns `response.usage || %{}`. Always use `Map.get(usage, :input_tokens, 0)` with defaults.

**`stream_text` does not return token counts.** `{:llm_done, …}` carries only the concatenated string. Count tokens client-side or use `generate_text` when usage data is needed.

**Circuit breaker caller responsibility.** Forgetting `record_success/failure` after a call means the breaker never learns about outcomes and stays closed indefinitely during outages.

**Recovery timeout is lazy.** After opening, the circuit stays open until the next `allow?` call after 30s. No periodic timer.

**`StreamHandler` task is detached.** Crashes are not surfaced to the caller. Always set a `Process.send_after/3` timeout in the LiveView's `handle_info`.
