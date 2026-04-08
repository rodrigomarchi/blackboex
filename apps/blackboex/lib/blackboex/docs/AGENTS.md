# AGENTS.md — Docs Context

Documentation generation for user-defined APIs. Facade: `Blackboex.Docs` (`docs.ex`).

## Modules

| Module | Purpose | File |
|--------|---------|------|
| `Docs` | Facade: `generate/2`, `generate_openapi/2` | `docs.ex` |
| `DocGenerator` | LLM-driven Markdown docs (batch or streaming) | `doc_generator.ex` |
| `OpenApiGenerator` | Deterministic OpenAPI 3.1 map (no LLM) | `open_api_generator.ex` |
| `DocPrompts` | Prompt builders + sanitization | `doc_prompts.ex` |

**Previously:** No facade — callers aliased leaf modules directly. Now use `Blackboex.Docs` facade.

## Public API (Facade)

```elixir
Docs.generate(api, opts \\ []) :: {:ok, %{doc: String.t(), usage: map()}} | {:error, term()}
Docs.generate_openapi(api, opts \\ []) :: map()
```

Options for `generate/2`: `:client` (LLM client, defaults to `Config.client/0`), `:token_callback` (activates streaming).

## DocGenerator

- Batch mode: `client.generate_text/2` → `{:ok, %{doc: string, usage: map}}`
- Streaming mode: `token_callback` provided → usage is always `%{}` (streaming doesn't surface token counts)
- Soft failure in pipeline: `documentation_md: nil` if doc generation fails, does not abort

## OpenApiGenerator

Deterministic, no LLM. Returns plain `map()` (JSON-serializable).

| `template_type` | Paths |
|----------------|-------|
| `"computation"` | `GET /`, `POST /` |
| `"crud"` | `GET /`, `POST /`, `GET /{id}`, `PUT /{id}`, `DELETE /{id}` |
| `"webhook"` | `POST /` only |

`to_json(spec)` and `to_yaml(spec)` for serialization. Served by `ApiDocsPlug` at `/api/:org/:slug/openapi.json|yaml|docs`.

## Security

`DocPrompts` sanitizes user data before embedding in prompts:
- `source_code`: triple backticks → spaced backticks (prevent code fence breakout)
- name/description: backticks stripped, capped at 10,000 chars

## Integration Points

- `Agent.CodePipeline` → `Docs.generate/2` (streaming, `token_callback` broadcasts to PubSub)
- `Agent.CodePipeline` → `Docs.generate/2` (via Generation.step_generate_docs)
- `Testing.TestGenerator` → `Docs.generate_openapi/2` (for test prompt context)
- `DocsLive` LiveView → `Docs.generate/2` via `Task.async`

## Gotchas

1. **Streaming usage is empty** — `usage: %{}` in streaming mode. Callers recording usage will record zeros.
2. **Stub Api in pipeline** — generates with `name: "API"`, `method: "POST"`, `requires_auth: true`. OpenAPI spec is for LLM context only.
3. **Mock LLM, not DocGenerator** — use `Blackboex.LLM.ClientMock` in tests. `DocGeneratorTest` uses `async: false` (global mock).
