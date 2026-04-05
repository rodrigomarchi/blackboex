# Testing Context — AGENTS.md

## Overview

The `Blackboex.Testing` context is the API test framework. It has two distinct responsibilities:

1. **LLM-generated unit tests** — given an API's source code, ask an LLM to generate an ExUnit test module that calls the handler functions directly (not via HTTP). Those tests are stored as `TestSuite` records and executed inside an isolated sandbox process with timeout and memory caps.

2. **HTTP request history** — record every manual test request a user fires from the request builder UI, storing the request (method, path, headers, body) and the response (status, headers, body). These are stored as `TestRequest` records.

The context has no Phoenix dependencies. The facade (`Blackboex.Testing`) is a thin Ecto wrapper with security transforms (header redaction, body truncation). All orchestration logic lives in the submodules.

---

## Key Modules

### `Blackboex.Testing` (facade — `testing.ex`)

The public API for the context. Wraps Ecto CRUD for both schemas and applies two security transforms automatically on `create_test_request/1`:

- **Header redaction** — any sensitive header (`authorization`, `cookie`, `x-api-key`, `x-auth-token`, `x-access-token`, `x-csrf-token`, `proxy-authorization`, `set-cookie`) is replaced with `"[REDACTED]"` before the record is persisted.
- **Body truncation** — response bodies larger than 65,536 bytes are silently truncated at the byte boundary before persistence.

These transforms are also exposed as public functions (`redact_headers/1`, `truncate_body/2`) so callers can apply them independently.

---

### `Blackboex.Testing.TestRunner` (`test_runner.ex`)

Executes LLM-generated ExUnit test code in an isolated process. This is the core execution engine.

**Responsibilities:**
- Validates syntax before attempting execution (`Code.string_to_quoted/1`).
- Spawns tests in a supervised `Task.Supervisor` task (`Blackboex.SandboxTaskSupervisor`) so they are isolated from the caller process.
- Enforces a per-task memory cap via `Process.flag(:max_heap_size, ...)`. Default 20 MB, hard cap 50 MB; exceeds → `{:error, :memory_exceeded}`.
- Enforces a configurable timeout. Default 30 s, hard cap 60 s; exceeds → `{:error, :timeout}`.
- Replaces `use ExUnit.Case` with `use Blackboex.Testing.SandboxCase` via regex before compilation to prevent auto-registration with ExUnit.
- Optionally compiles the API's handler source code into a `Handler` module before tests run, so tests can call `Handler.handle(params)` directly.
- Purges all compiled modules from the BEAM after each run to prevent module leaks between runs.

**Return type:**
```elixir
{:ok, [test_result()]}
| {:error, :compile_error, String.t()}
| {:error, :timeout}
| {:error, :memory_exceeded}
```

where `test_result()` is `%{name: String.t(), status: String.t(), duration_ms: non_neg_integer(), error: String.t() | nil}`.

---

### `Blackboex.Testing.TestGenerator` (`test_generator.ex`)

Calls the LLM to generate an ExUnit test module for a given API. Includes a compile-check retry loop.

**Flow:**
1. Build an OpenAPI spec from the API via `Docs.OpenApiGenerator.generate/2`.
2. Build the generation prompt via `TestPrompts.build_generation_prompt/2`.
3. Call the LLM (blocking or streaming).
4. Parse the `elixir` code fence from the response via `TestPrompts.parse_response/1`.
5. Syntax-check the extracted code with `Code.string_to_quoted/1`.
6. If a compile error is found, build a retry prompt (`TestPrompts.build_retry_prompt/2`) and call the LLM again — up to **3 retries**.
7. On success return `{:ok, %{code: String.t(), usage: map()}}` where `usage` accumulates token counts across all LLM calls.

**Entry points:**
- `generate_tests(%Api{}, opts)` — primary path, takes a full `Api` struct.
- `generate_tests_for_code(source_code, template_type, opts)` — convenience wrapper that constructs a synthetic `Api` struct; used when the caller only has raw source.

**LLM options (passed via `opts`):**
- `:client` — LLM client module (defaults to `LLM.Config.client/0`).
- `:token_callback` — if present, switches to streaming mode; tokens are fed to this function one by one.

---

### `Blackboex.Testing.TestSuite` (`test_suite.ex`)

Ecto schema. One record per LLM-generated test generation run for an API.

**Table:** `test_suites`

| Field | Type | Notes |
|-------|------|-------|
| `id` | `binary_id` | UUID primary key |
| `api_id` | `binary_id` | FK → `apis`, required |
| `version_number` | `integer` | API version at generation time; unique per `(api_id, version_number)` |
| `test_code` | `string` | The LLM-generated ExUnit source; required; max 1,048,576 bytes |
| `status` | `string` | Lifecycle: `pending \| running \| passed \| failed \| error`; default `"pending"` |
| `results` | `{:array, :map}` | Per-test result maps from `TestRunner`; default `[]` |
| `total_tests` | `integer` | Aggregate count; default `0` |
| `passed_tests` | `integer` | Aggregate count; default `0` |
| `failed_tests` | `integer` | Aggregate count; default `0` |
| `duration_ms` | `integer` | Total wall time of the run; default `0` |
| `inserted_at` | `naive_datetime` | |
| `updated_at` | `naive_datetime` | |

Constraints: `status` must be one of the five valid values; all count fields must be `>= 0`; unique index on `(api_id, version_number)`.

---

### `Blackboex.Testing.TestRequest` (`test_request.ex`)

Ecto schema. One record per manual HTTP test request sent from the UI.

**Table:** `test_requests`

| Field | Type | Notes |
|-------|------|-------|
| `id` | `binary_id` | UUID primary key |
| `api_id` | `binary_id` | FK → `apis`, required |
| `user_id` | `id` (integer) | FK → `users`, optional |
| `method` | `string` | `GET \| POST \| PUT \| PATCH \| DELETE`; required |
| `path` | `string` | Required; max 2,048 chars |
| `headers` | `map` | Request headers (sensitive ones redacted by facade); default `%{}` |
| `body` | `string` | Request body; max 1,048,576 bytes |
| `response_status` | `integer` | HTTP status code |
| `response_headers` | `map` | Response headers; default `%{}` |
| `response_body` | `string` | Truncated to 65,536 bytes by facade before insert |
| `duration_ms` | `integer` | Round-trip time |
| `inserted_at` | `naive_datetime` | Insert-only (`updated_at: false`) |

Both `headers` and `response_headers` are validated with `validate_json_size/2` (from `ChangesetHelpers`) to prevent oversized JSONB payloads.

---

### `Blackboex.Testing.TestPrompts` (`test_prompts.ex`)

Prompt engineering layer for test generation. Stateless — all functions are pure.

**Functions:**
- `system_prompt/0` — The LLM system persona. 200+ line instruction set covering test coverage categories, ExUnit patterns, nested schema patterns, float comparison gotchas, forbidden libraries, and output format (`elixir` code fence only).
- `build_generation_prompt/2` — User message combining API name, type, description, source code (code fence sanitized), and a template-type-specific function hint.
- `build_retry_prompt/2` — User message containing the failing code and the exact compile error, asking the LLM to return a corrected module.
- `parse_response/1` — Extracts the content of the first `elixir` (or bare) code fence using a regex. Returns `{:ok, code}` or `{:error, :no_code_found}`.

**Template-type function hints:**
- `"crud"` — hints `handle_list`, `handle_get`, `handle_create`, `handle_update`, `handle_delete`
- `"webhook"` — hints `handle_webhook`
- anything else — hints `handle`

Code fence injection attacks are neutralized: backticks in source code are replaced with `"` ` ` `"` before being interpolated into prompts. API name/description fields are stripped of backticks and truncated to 10,000 chars.

---

### `Blackboex.Testing.ResponseValidator` (`response_validator.ex`)

Validates an HTTP response against a flat `param_schema` map (field name → type string). Used for manual test request validation.

**Input:** `%{status: integer(), body: binary()}` + schema `%{field_name => type_string}`

**Validation:**
1. **Status check** — must be `2xx`; otherwise produces a `:unexpected_status` violation.
2. **JSON parse** — body must be valid JSON and decode to a map; otherwise `:invalid_json` violation.
3. **Missing fields** — any key in `schema` absent from the parsed response body produces `:missing_field`.
4. **Wrong types** — any key present but with the wrong type produces `:wrong_type`.

Type strings recognized: `"string"`, `"integer"`, `"number"`, `"boolean"`, `"array"`, `"object"`. Unknown type strings always pass.

Returns `[]` when schema is `nil` or empty.

---

### `Blackboex.Testing.ContractValidator` (`contract_validator.ex`)

Validates an HTTP response against a full OpenAPI spec using `ExJsonSchema`. Used for richer contract validation.

**Input:** `%{status: integer(), body: map()}` (body must already be decoded) + `openapi_spec` map.

**Flow:**
1. Navigate the spec to find the first `paths` key → first method → `responses`.
2. Check whether the actual status code is documented; if not, return an `:undocumented_status` violation.
3. Extract the `application/json` schema for the matching status code.
4. Resolve the schema with `ExJsonSchema.Schema.resolve/1` and validate.
5. Map any ExJsonSchema errors to `%{type: :schema_violation, message: ..., path: ...}` violations.

**`extract_response_schema/2`** — public helper to pull just the schema map for a given status code without validating.

**Safety:** If the body is `nil` or a binary (not a map), validation is skipped entirely — clause guard prevents a crash from calling `ExJsonSchema` on non-map data.

---

### `Blackboex.Testing.RequestExecutor` (`request_executor.ex`)

Executes HTTP requests against deployed API endpoints with SSRF protection.

**SSRF guard:** Only allows relative paths matching `^/api/[^/]+/[^/]+`. Any URL with a scheme (`http://`, `https://`) or host component is rejected with `{:error, :forbidden}`. Protocol-relative URLs are also blocked because `URI.parse` would leave `scheme` nil but set `host`.

**Execution:**
- Uses `Req` library with `decode_body: false` and `retry: false`.
- Measures round-trip duration with `:timer.tc`.
- Supports a `:plug` opt for in-process testing (passes the plug directly to Req, bypassing real HTTP).
- Supports a `:base_url` opt to prepend to the relative path.
- Default timeout 30 s.

**Returns:**
```elixir
{:ok, %{status: integer(), headers: map(), body: binary(), duration_ms: integer()}}
| {:error, :timeout | :connection_error | :forbidden}
```

---

### `Blackboex.Testing.SampleData` (`sample_data.ex`)

Generates test request payloads from an API's schema metadata. Purely in-memory — no LLM involved.

**Dispatch logic (input is an API-like map):**
- If `param_schema` is a non-empty map → generate from schema.
- Else if `example_request` is a non-empty map → use it as the happy path, infer schema from it to generate edge cases.
- Otherwise → return empty result.

**Output type:**
```elixir
%{
  happy_path: map(),        # one valid sample with canonical values
  edge_cases: [map()],      # one map per (field, edge_value) combination
  invalid: [map()]          # one map per field with a wrong-type value
}
```

**Edge values generated per type:**

| Type | Edge values |
|------|-------------|
| `"string"` | `""`, `nil`, 1001-char string, Unicode accents, emoji, SQL injection, XSS payload |
| `"integer"` | `0`, `-1`, `nil`, `-999_999`, `999_999_999` |
| `"number"` | `0`, `0.0`, `-1.5`, `nil`, `999_999_999.99` |
| `"boolean"` | `false`, `nil` |
| others | `nil`, `""` |

---

### `Blackboex.Testing.SnippetGenerator` (`snippet_generator.ex`)

Generates ready-to-use code snippets in six languages for consuming an API endpoint. All user-controlled values are escaped for each target language to prevent code injection.

**Supported languages:** `:curl`, `:python`, `:javascript`, `:elixir`, `:ruby`, `:go`

**Entry point:** `generate(api, language, request)` where `request` is a map with keys `:method`, `:url`, `:headers`, `:body`, `:api_key`.

**Security:**
- Shell (cURL): single-quote wrap + `'` → `'\''`.
- Python/Ruby: backslash and single-quote escaping.
- JavaScript: backslash, single-quote, and newline escaping.
- Go: double-quote and newline escaping; backtick strings use string concatenation to escape embedded backticks.

If `:api_key` is present in the request map, it is injected as the `X-Api-Key` header automatically in all languages.

`valid_language?/1` — guard helper for controllers to reject unknown language atoms.

---

### `Blackboex.Testing.TestFormatter` (`test_formatter.ex`)

A GenServer implementing the ExUnit formatter protocol. Collects per-test results during an ExUnit run and exposes them via `get_results/1`.

**Events handled:** `:test_finished`, `:suite_finished`, `:suite_started`, `:module_started`, `:module_finished`, and a catch-all `_event`.

**Status mapping:**
- `nil` → `"passed"`
- `{:excluded, _}` → `"excluded"`
- `{:skipped, _}` → `"skipped"`
- `{:failed, _}` → `"failed"`
- `{:invalid, _}` → `"error"`

Note: `TestFormatter` follows the ExUnit formatter protocol but is **not currently wired into the `TestRunner` execution path** — `TestRunner` executes tests by directly calling the test functions (not by running ExUnit). `TestFormatter` is retained for future ExUnit-native execution modes.

---

### `Blackboex.Testing.SandboxCase` (`sandbox_case.ex`)

A lightweight `use`-able macro module that replaces `ExUnit.Case` in sandboxed test code. Prevents generated tests from registering themselves with ExUnit's global server.

**What `use Blackboex.Testing.SandboxCase` provides:**
- `import ExUnit.Assertions` — so `assert`, `refute`, etc. are available.
- `test/2` macro — defines a function named `:"test <name>"` with arity 1 (accepting a context map). This name format is what `TestRunner.extract_test_functions/1` looks for.
- `describe/2` macro — a no-op grouping macro that simply expands its block inline (no ExUnit grouping needed since we're not using ExUnit's runner).

The injection prevention chain: `TestRunner.deregister_exunit/1` runs a regex replacement over the test source (`use ExUnit.Case` → `use Blackboex.Testing.SandboxCase`) before compilation.

---

## Test Execution Flow

End-to-end flow for LLM-generated unit test execution:

```
1. Caller invokes TestGenerator.generate_tests(%Api{}, opts)
   |
   +-> OpenApiGenerator.generate(api) — build OpenAPI spec map
   +-> TestPrompts.build_generation_prompt(api, openapi_spec)
   +-> LLM call (blocking or streaming)
   +-> TestPrompts.parse_response(llm_output) — extract elixir code fence
   +-> Code.string_to_quoted(code) — syntax check
       |
       +-- compile error? --> build_retry_prompt + LLM retry (max 3 attempts)
       |
       +-- ok --> {:ok, %{code: ..., usage: ...}}

2. Caller creates a TestSuite record via Testing.create_test_suite/1
   with status "pending" and the generated code.

3. Caller invokes TestRunner.run(test_code, handler_code: api.source_code)
   |
   +-> Code.string_to_quoted(test_code) — gate on syntax
   +-> Task.Supervisor.async_nolink(Blackboex.SandboxTaskSupervisor, fn ->
         Process.flag(:max_heap_size, ...)     -- memory cap
         compile_handler_module(handler_code)  -- compile Handler module
         deregister_exunit(test_code)          -- patch use ExUnit.Case
         Code.compile_string(safe_code)        -- compile test module
         extract_test_functions(mod)           -- find "test *"/1 functions
         Enum.map(test_fns, run_single_test)   -- execute each, time it
         purge_modules(all_compiled)           -- clean BEAM
       end)
   +-> Task.yield(task, timeout) or Task.shutdown(:brutal_kill)
   |
   +-- {:ok, results} --> {:ok, [test_result()]}
   +-- {:exit, :killed} --> {:error, :memory_exceeded}
   +-- nil (timeout) --> {:error, :timeout}

4. Caller updates TestSuite with results, status, and aggregated counts.
```

---

## Validation Logic

### ResponseValidator — flat schema validation

Used for lightweight validation of manual test requests.

- Only validates map-shaped JSON responses.
- Checks for missing fields (keys in schema absent from response).
- Checks for type mismatches. Type strings: `"string"`, `"integer"`, `"number"`, `"boolean"`, `"array"`, `"object"`.
- Short-circuits: returns `[]` when schema is nil or `%{}`.
- Does **not** validate nested fields.

### ContractValidator — OpenAPI schema validation

Used for full contract compliance against an OpenAPI spec.

- Requires the response body to be a decoded map (`is_map/1` guard on the clause head).
- Navigates `paths -> first_path -> first_method -> responses`.
- Checks the actual HTTP status against documented response codes.
- If status is undocumented, returns a single `:undocumented_status` violation and stops.
- If status is documented, extracts `content.application/json.schema` and runs it through `ExJsonSchema`.
- Returns `[]` for nil/binary bodies without crashing.

---

## Public API (Facade)

All functions in `Blackboex.Testing`:

```elixir
# TestSuite CRUD
@spec create_test_suite(map()) :: {:ok, TestSuite.t()} | {:error, Ecto.Changeset.t()}
@spec update_test_suite(TestSuite.t(), map()) :: {:ok, TestSuite.t()} | {:error, Ecto.Changeset.t()}
@spec list_test_suites(api_id :: binary(), limit :: non_neg_integer()) :: [TestSuite.t()]
@spec get_test_suite(id :: binary()) :: {:ok, TestSuite.t()} | {:error, :not_found}
@spec get_latest_test_suite(api_id :: binary()) :: TestSuite.t() | nil

# TestRequest CRUD
@spec create_test_request(map()) :: {:ok, TestRequest.t()} | {:error, Ecto.Changeset.t()}
@spec list_test_requests(api_id :: binary(), limit :: non_neg_integer()) :: [TestRequest.t()]
@spec get_test_request(id :: binary()) :: {:ok, TestRequest.t()} | {:error, :not_found}
@spec clear_history(api_id :: binary()) :: {:ok, non_neg_integer()}

# Security transforms (also applied automatically in create_test_request)
@spec redact_headers(map()) :: map()
@spec truncate_body(binary() | nil, max :: non_neg_integer()) :: binary() | nil
```

Default limits: `list_test_suites/2` → 10, `list_test_requests/2` → 50. Both queries order by `inserted_at DESC, id DESC` for stable pagination.

---

## Integration with Other Contexts

### Apis context

- `TestSuite` has a `belongs_to :api` FK. The facade queries are always scoped by `api_id`.
- `TestGenerator` receives an `%Apis.Api{}` struct directly and reads `source_code`, `template_type`, `name`, `description`.
- `TestRequest` belongs to an API; `clear_history/1` deletes all test requests for a given API.

### Docs context

- `TestGenerator` calls `Docs.OpenApiGenerator.generate(api, opts)` to build the OpenAPI spec that is passed to the generation prompt. This keeps prompt construction decoupled from spec generation.

### CodeGen context

No direct dependency at runtime. However, test generation is conceptually downstream of `CodeGen` — an API must be compiled before its handler source code can be meaningfully tested. The `TestRunner` recompiles the handler source code into a temporary `Handler` module at test execution time.

### Agent context

`Agent.CodePipeline` and `Agent.Session` do not call `Testing` directly, but the convention is that after an API reaches the `compiled` or `published` lifecycle state, test generation can be triggered. The integration point is at the LiveView layer, not in domain code.

### LLM context

`TestGenerator` uses `LLM.Config.client/0` to resolve the active LLM client. It supports both `generate_text/2` (blocking) and `stream_text/2` (streaming via `token_callback` opt). Usage tokens are accumulated and returned in `%{usage: %{input_tokens: n, output_tokens: n}}`.

---

## Gotchas

### ContractValidator — nil body crash
`ContractValidator.validate/2` dispatches on `%{status: _, body: map()}`. If the body is `nil` or a binary string (e.g., the response body was not yet JSON-decoded by the caller), the second clause matches and returns `[]` silently. Callers must decode the body before calling `ContractValidator` if they want schema validation. `ResponseValidator` is the right choice when the body is still a binary.

### Empty test module false positive
`TestRunner` raises `{:error, :compile_error, "No test functions found in compiled code"}` if the compiled module has no functions matching `"test "/1`. This can happen when:
- The LLM generates a module with `describe` blocks but no `test` macros inside them.
- The LLM uses `test "name", context do` (arity-2 style) which SandboxCase does not define.
- The test code compiles successfully but all test functions have arity != 1.

The check is `arity == 1 and String.starts_with?(Atom.to_string(name), "test ")`. Any other naming pattern is invisible to the runner.

### Module leak between runs
`TestRunner` calls `purge_modules/1` in the success path. However, if a crash occurs in `run_in_process/2` before reaching `purge_modules`, the compiled modules remain in the BEAM for the lifetime of the node. The `rescue` block in `run_in_process/2` does not purge because the module list may not be available in the error path. This is a known minor leak; modules are garbage-collected at node restart.

### Handler module name collision
`compile_handler_module/1` always compiles the handler into a module named exactly `Handler`. If two concurrent `TestRunner` tasks are running simultaneously for different APIs, they will overwrite each other's `Handler` module. The `Blackboex.SandboxTaskSupervisor` does not enforce serialization. This is safe in practice only if the platform ensures single-tenant test execution.

### Timeout is capped, not rejected
If a caller passes `timeout: 120_000` (2 minutes), `TestRunner` silently clamps it to `@max_timeout` (60,000 ms) without returning an error or warning. Callers should not assume their requested timeout is honored.

### Memory cap kills the process, not the task
When a sandboxed process exceeds `max_heap_size`, the BEAM kills it with reason `:killed`. `TestRunner` catches this as `{:exit, :killed}` and returns `{:error, :memory_exceeded}`. The task's compiled modules are not purged in this path (same leak as above).

### Float comparison in generated tests
`TestPrompts.system_prompt/0` explicitly instructs the LLM not to use `==` for float comparisons. However, the LLM may still generate `assert result == 1.5` which will fail nondeterministically due to floating-point arithmetic. If tests generated for computation-heavy APIs (pricing, financial) fail intermittently, check for exact float equality assertions.

### Header redaction is key-case-sensitive only on the comparison
`redact_headers/1` normalizes the comparison with `String.downcase(key)` but preserves the original key in the output map. A header stored as `"Authorization"` is redacted but stored back as `"Authorization"` (not lowercased). This is correct behavior but can be surprising when inspecting records.

### `test_code` size limit
`TestSuite.changeset/2` enforces `validate_length(:test_code, max: 1_048_576)` (1 MB). The LLM system prompt instructs generation of comprehensive tests covering 7 test categories; for complex APIs with many nested schemas, the generated code can approach this limit.
