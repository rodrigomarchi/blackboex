# AGENTS.md — LLM Context

AI model interface layer. Facade: `Blackboex.LLM` (`llm.ex`).

## Request Flow

```
1. LLM.allow?(user_id, plan)                             ← RateLimiter check
2. LLM.CircuitBreaker.allow?(provider)                   ← reject if open
3. {:ok, client, opts} = LLM.Config.client_for_project(project_id)
4. client.generate_text(prompt, Keyword.merge(opts, user_opts))
5. on success: LLM.record_success(provider) + LLM.record_usage(attrs)
   on failure: LLM.record_failure(provider)
```

### Per-project API key

There is **no platform Anthropic key**. Every caller must thread `project_id`
down to `LLM.Config.client_for_project/1`, which resolves:

- `{:ok, client, [api_key: plaintext]}` when the project has an Anthropic key
  configured via `ProjectEnvVars.put_llm_key/4`
- `{:error, :not_configured}` when the project has no key — callers surface
  this to the UI via the `llm_not_configured_banner` component

In test env, when `client()` resolves to `Blackboex.LLM.ClientMock` and no
key is configured, a dummy key is returned. Production always enforces
`:not_configured`.

### Legacy `Config.client/0`

The old `Config.client/0` is still exported (returns the resolved client
module), but callers **must** use `client_for_project/1` to obtain the
api_key opts. Never call `ReqLLMClient` directly — the client would have no
key to use.

## LLM Facade (`llm.ex`)

The facade now exposes circuit breaker and rate limiter operations directly:

```elixir
LLM.record_usage(attrs)                    # persists LLM.Usage record
LLM.allow?(user_id, plan)                 # RateLimiter.check_rate/2
LLM.record_success(provider)              # CircuitBreaker.record_success/1
LLM.record_failure(provider)              # CircuitBreaker.record_failure/1
LLM.allowed_modules()                     # delegates to SecurityConfig
LLM.prohibited_modules()                  # delegates to SecurityConfig
```

## SecurityConfig — Single Source of Truth

`Blackboex.LLM.SecurityConfig` owns the allowed/prohibited module lists.

```elixir
SecurityConfig.allowed_modules() :: [String.t()]
SecurityConfig.prohibited_modules() :: [String.t()]
```

**Rule:** Never duplicate these lists. `AstValidator` reads from `SecurityConfig`. `Prompts` reads from `SecurityConfig`. Do NOT define `allowed_modules/0` or `prohibited_modules/0` in `Prompts` or anywhere else.

## Key Modules

| Module | Purpose |
|--------|---------|
| `SecurityConfig` | Single source for allowed/prohibited module lists |
| `Config` | `client/0` — resolves mock in test, `ReqLLMClient` in prod |
| `CircuitBreaker` | GenServer. Per-provider health: closed/open/half_open |
| `RateLimiter` | Per-user token bucket (ExRated). `check_rate(user_id, plan)` |
| `PromptFragments` | Canonical source for shared prompt text fragments (handler rules, code quality, etc.) |
| `PromptParsers` | Response parsing (code blocks, SEARCH/REPLACE, sanitization) |
| `Prompts` | System prompts and generation prompt builders (composes from PromptFragments) |
| `EditPrompts` | SEARCH/REPLACE diff format for conversational editing |
| `StreamHandler` | Fire-and-forget streaming task |
| `Usage` | Schema for `llm_usage` table |

## CircuitBreaker States

```
closed ──[5 failures in 60s]──► open ──[30s]──► half_open ──[2 successes]──► closed
```

Caller is responsible for `allow?` before and `record_success/failure` after every LLM call.

## Rate Limits

| Plan | Requests/hour |
|------|--------------|
| `:free` | 10 |
| `:pro` | 100 |
| `:enterprise` | 1_000 |

## Gotchas

1. **Never call `ReqLLMClient` directly** — always use `Config.client()`.
2. **`Prompts` no longer owns module lists** — `SecurityConfig` does. Check before adding to Prompts.
3. **`usage` map may be empty** — always use `Map.get(usage, :input_tokens, 0)` with defaults.
4. **`StreamHandler` task is detached** — always set a `Process.send_after/3` timeout in LiveView.
5. **Recovery timeout is lazy** — circuit stays open until next `allow?` call after 30s.
