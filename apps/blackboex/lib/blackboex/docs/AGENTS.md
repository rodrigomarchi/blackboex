# AGENTS.md — Blackboex.Docs

Context for AI agents working in `apps/blackboex/lib/blackboex/docs/`.

## Overview

The `Docs` context is responsible for automatic documentation generation for user-defined APIs. It has two responsibilities:

1. **Markdown documentation** — LLM-driven generation of rich human-readable docs (descriptions, endpoints, code examples, error tables). Result is stored in `Api.documentation_md`.
2. **OpenAPI specification** — Deterministic (no LLM) generation of OpenAPI 3.1 specs as plain maps. Used both as input to the markdown generator and as a public artifact served to end users.

There is no facade module (`Blackboex.Docs`). Callers alias the leaf modules directly.

## Files

| File | Module | Role |
|---|---|---|
| `doc_generator.ex` | `Blackboex.Docs.DocGenerator` | LLM call + streaming/batch dispatch |
| `doc_prompts.ex` | `Blackboex.Docs.DocPrompts` | Prompt templates + sanitization |
| `open_api_generator.ex` | `Blackboex.Docs.OpenApiGenerator` | Deterministic OpenAPI 3.1 map builder |

---

## DocGenerator

Generates Markdown documentation for a given `Api` struct by calling the LLM.

### Entry Point

```elixir
@spec generate(Api.t(), keyword()) :: {:ok, %{doc: String.t(), usage: map()}} | {:error, term()}
def generate(%Api{} = api, opts \\ [])
```

**Options:**

| Key | Type | Default | Description |
|---|---|---|---|
| `:client` | LLM client | `Config.client/0` | Injectable LLM client (for testing via Mox) |
| `:token_callback` | `(String.t() -> any()) \| nil` | `nil` | When provided, activates streaming mode and calls the callback for each token |

### Execution Modes

**Batch mode** (no `:token_callback`):

- Calls `client.generate_text(prompt, system: system)`
- Returns `{:ok, %{doc: trimmed_content, usage: usage_map}}`
- Errors map to `{:error, :generation_failed}`

**Streaming mode** (`:token_callback` provided):

- Calls `client.stream_text(prompt, system: system)`
- Handles two stream shapes:
  - `%ReqLLM.StreamResponse{}` — consumes via `ReqLLM.StreamResponse.tokens/1`
  - Plain enumerable of `{:token, token}` tuples (mock/test streams)
- Returns `{:ok, %{doc: trimmed_full_text, usage: %{}}}` (usage is empty in streaming path)
- Errors map to `{:error, :generation_failed}`

### Internal Flow

```
generate/2
  └── OpenApiGenerator.generate(api, opts)   # build spec first
  └── DocPrompts.build_doc_prompt(api, spec) # build user prompt
  └── DocPrompts.system_prompt()             # build system prompt
  └── generate_batch/3 or generate_streaming/4
```

---

## OpenApiGenerator

Deterministic, no-LLM generation of OpenAPI 3.1 specs as plain `map()`. No external dependencies beyond `Jason` (for `to_json/1`) and `Ymlr` (for `to_yaml/1`).

### Public API

```elixir
@spec generate(Api.t(), keyword()) :: map()
def generate(%Api{} = api, opts \\ [])

@spec to_json(map()) :: String.t()
def to_json(spec)

@spec to_yaml(map()) :: String.t()
def to_yaml(spec)
```

**Options for `generate/2`:**

| Key | Type | Description |
|---|---|---|
| `:base_url` | `String.t() \| nil` | If given, included in `servers` array. If nil, `servers` is `[]`. |

### Spec Structure

The returned map always contains these top-level keys:

```json
{
  "openapi": "3.1.0",
  "info":       { "title", "version", "description?" },
  "servers":    [ { "url" } ] | [],
  "paths":      { ... },
  "components": { "securitySchemes"? },
  "security":   [ { "bearerAuth": [] } ] | []
}
```

### Path Shape by Template Type

| `template_type` | Paths generated |
|---|---|
| `"computation"` | `GET /`, `POST /` |
| `"crud"` | `GET /`, `POST /` at `/`; `GET /{id}`, `PUT /{id}`, `DELETE /{id}` at `/{id}` |
| `"webhook"` | `POST /` only |

### Schema Mapping

`Api.param_schema` is a `%{field_name => type_string}` map. Type strings are normalized to JSON Schema types:

| Elixir type string | JSON Schema type |
|---|---|
| `"integer"` | `"integer"` |
| `"float"`, `"number"` | `"number"` |
| `"boolean"` | `"boolean"` |
| `"array"` | `"array"` |
| `"map"`, `"object"` | `"object"` |
| anything else | `"string"` |

`nil` param_schema or empty map → `requestBody` is omitted (no body for that operation).

### Authentication

When `api.requires_auth == true`:

- `components.securitySchemes.bearerAuth` is added (HTTP bearer scheme; callers use `bb_live_*` API keys as the Bearer token)
- `security: [%{"bearerAuth" => []}]` is set at spec root

When `requires_auth == false`: both `components` and `security` are empty.

### Request/Response Examples

- If `api.example_request` is set, it is embedded as `requestBody.content["application/json"].example`
- If `api.example_response` is set, it is embedded as `responses.200.content["application/json"].example`
- Standard error responses `400` and `500` are always present

---

## DocPrompts

Builds the two prompt strings passed to the LLM by `DocGenerator`.

### Public API

```elixir
@spec system_prompt() :: String.t()
def system_prompt()

@spec build_doc_prompt(Api.t(), map()) :: String.t()
def build_doc_prompt(%Api{} = api, openapi_spec)
```

### System Prompt

Instructs the LLM to act as a technical writer. Requirements it enforces:

- Clear, concise English
- All sections: description, authentication, endpoints, request/response examples, error codes, rate limiting, code examples
- Proper Markdown with headers, code blocks, and tables
- Code examples in four languages: cURL, Python (requests), JavaScript (fetch), Elixir (Req)
- Return ONLY the Markdown content — no preamble or meta-commentary

### User Prompt (`build_doc_prompt/2`)

Embeds these fields from the `Api` struct:

| Field | Sanitization |
|---|---|
| `api.name` | Backticks stripped, capped at 10 000 chars |
| `api.description` | Same; falls back to `"No description provided"` |
| `api.template_type` | Embedded verbatim |
| `api.method` | Embedded verbatim |
| `api.requires_auth` | Embedded verbatim |
| `api.source_code` | Triple backticks replaced with `" \` \` \` "` to prevent prompt injection via code fence breakout |

The OpenAPI spec (`openapi_spec`) is JSON-encoded with `Jason.encode!(spec, pretty: true)` and embedded in a fenced code block.

### Security — Prompt Injection Guards

Two sanitization functions are applied before embedding user data:

- `sanitize_code_fence/1` — replaces ```` ``` ```` with `` ` ` ` `` in `source_code` to prevent breaking the prompt's fenced block
- `sanitize_field/1` — strips all backtick characters from name/description fields and caps at 10 000 characters

---

## Public API Summary

```elixir
# Generate Markdown docs (batch)
DocGenerator.generate(api)
# => {:ok, %{doc: "# My API\n...", usage: %{input_tokens: 120, output_tokens: 800}}}

# Generate Markdown docs (streaming)
DocGenerator.generate(api, token_callback: fn token -> send(self(), {:token, token}) end)
# => {:ok, %{doc: "# My API\n...", usage: %{}}}

# Generate OpenAPI spec map
OpenApiGenerator.generate(api, base_url: "https://api.example.com/api/org/slug")
# => %{"openapi" => "3.1.0", "info" => ..., "paths" => ..., ...}

# Serialize spec
OpenApiGenerator.to_json(spec)   # => JSON string
OpenApiGenerator.to_yaml(spec)   # => YAML string
```

---

## Integration

### Called by Agent.CodePipeline

`Agent.CodePipeline` (`apps/blackboex/lib/blackboex/agent/code_pipeline.ex`) calls `DocGenerator.generate/2` as one step in the streaming code generation flow. It:

1. Constructs an `%Api{}` with the generated source code
2. Passes a `token_callback` that broadcasts tokens over PubSub for real-time UI updates
3. Stores the resulting markdown in `documentation_md` on the persisted `Api` record

Relevant step in the pipeline: `step_generate_docs/4`.

### Called by CodeGen.UnifiedPipeline

`CodeGen.UnifiedPipeline` (`apps/blackboex/lib/blackboex/code_gen/unified_pipeline.ex`) calls `DocGenerator.generate/2` via the private `generate_documentation/2` helper. This runs as the `:generating_docs` step after the validation loop succeeds. It synthesizes a temporary `%Api{}` stub from `ctx.code` and `ctx.template_type` — the stub uses generated UUIDs and placeholder values, so the resulting docs describe code structure rather than a real persisted API.

The `documentation_md` key in the `result` map is set to `nil` if doc generation fails (soft failure — does not abort the pipeline).

### Called by DocsLive (LiveView)

`BlackboexWeb.ApiLive.Edit.DocsLive` allows on-demand regeneration:

- User triggers `"generate_docs"` event
- Billing gate: `Enforcement.check_limit(org, :llm_generation)` checked first
- `Task.async(fn -> DocGenerator.generate(api) end)` — non-blocking, result received via `handle_info`
- On success: `Apis.update_api(api, %{documentation_md: markdown})` persists the result
- Usage recorded via `LLM.record_usage/1`

### Called by Testing.TestGenerator

`Testing.TestGenerator` uses `OpenApiGenerator.generate/2` to build the OpenAPI spec that is embedded in the test generation prompt. This gives the LLM context about API shape (paths, methods, schemas) when generating ExUnit tests.

### Served by ApiDocsPlug

`BlackboexWeb.Plugs.ApiDocsPlug` serves the OpenAPI spec over HTTP for published APIs:

| Route | Content-Type | Method |
|---|---|---|
| `GET /api/:org/:slug/openapi.json` | `application/json` | `serve_spec_json/4` |
| `GET /api/:org/:slug/openapi.yaml` | `text/yaml` | `serve_spec_yaml/4` |
| `GET /api/:org/:slug/docs` | `text/html` | `serve_swagger_ui/4` |

The plug builds the `base_url` from the live request connection (`conn.scheme`, `conn.host`, `conn.port`) so the spec always reflects the correct server URL.

The Swagger UI uses `swagger-ui-dist@5` from unpkg.com, with the topbar hidden and `tryItOutEnabled: true`.

---

## Output Format

### Markdown documentation (`Doc`)

The LLM is instructed to produce a Markdown document with these sections (order may vary):

1. Title and description
2. Authentication — whether required, how to pass the key
3. Endpoints — method, path, parameters, request body schema
4. Request/Response examples — formatted JSON
5. Error codes — table of HTTP status codes
6. Rate limiting
7. Code examples — cURL, Python (requests), JavaScript (fetch), Elixir (Req)

Stored as raw Markdown in `Api.documentation_md`. Rendered in the LiveView via `render_markdown/1` (MDEx-based) and displayed in a `prose prose-sm dark:prose-invert` Tailwind container.

### OpenAPI Specification (`OpenApiGenerator`)

Plain Elixir map, JSON-serializable. Structure follows OpenAPI 3.1.0. Can be serialized to JSON via `to_json/1` or YAML via `to_yaml/1`.

---

## Gotchas

### Template Alignment

The system prompt and user prompt must stay aligned. The system prompt mandates specific sections (authentication, endpoints, error codes, code examples in four languages). If the user prompt omits fields (e.g., `source_code` is `nil`), the LLM receives placeholder text (`"# No source code available"`) and will generate generic documentation. The output quality degrades significantly when `source_code`, `param_schema`, and `example_request`/`example_response` are all absent.

### Streaming Usage Is Empty

In streaming mode, `usage` is always returned as `%{}` — the LLM client does not surface token counts for streamed responses. Callers that record usage (like `DocsLive`) will record zeros for streaming-sourced docs. This is intentional, not a bug.

### Stub Api in UnifiedPipeline

`CodeGen.UnifiedPipeline.generate_documentation/2` constructs a throwaway `%Api{}` with generated UUIDs and hardcoded values (`name: "API"`, `method: "POST"`, `requires_auth: true`). The resulting OpenAPI spec embedded in the doc prompt will always show auth as required and method as POST regardless of the actual API configuration. The OpenAPI spec used here is for LLM context only, not for public serving.

### No Facade Module

There is no `Blackboex.Docs` module. All callers must alias `Blackboex.Docs.DocGenerator` or `Blackboex.Docs.OpenApiGenerator` directly. This is consistent with how the codebase is structured (leaf module aliases) but means there is no single integration point to mock in tests — mock the LLM client via `Blackboex.LLM.ClientMock` instead.

### Code Fence Breakout

User-supplied `source_code` is sanitized before embedding in the prompt. Triple backticks are replaced with spaced backticks (`` ` ` ` ``). Without this, a malicious user could insert ```` ``` ```` into their source code to break out of the fenced block and inject arbitrary instructions into the LLM prompt. Name and description fields are also stripped of backticks.

### Ymlr Dependency

`to_yaml/1` depends on the `ymlr` hex package. Ensure it is present in `apps/blackboex/mix.exs`. If omitted, `OpenApiGenerator.to_yaml/1` will fail at runtime (not compile time).

### Test Mode

`DocGeneratorTest` uses `async: false` (Mox global mock for `ClientMock`). `OpenApiGeneratorTest` is `async: true` (no LLM, fully deterministic). Do not change `DocGeneratorTest` to `async: true` without switching to private Mox mocks.
