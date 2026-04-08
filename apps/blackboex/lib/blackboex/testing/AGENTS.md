# AGENTS.md — Testing Context

API test framework. Facade: `Blackboex.Testing` (`testing.ex`).

## Query Module

`TestingQueries` — all `Ecto.Query` composition for test suites and test requests. Sub-modules call `TestingQueries`, not inline queries.

## Two Responsibilities

1. **LLM-generated unit tests** — `TestGenerator` asks LLM to write ExUnit tests for an API's handler. Stored as `TestSuite`, executed in `TestRunner` sandbox.
2. **HTTP request history** — `TestRequest` records manual test requests from the UI (method, path, headers, body, response).

## Key Modules

| Module | Purpose |
|--------|---------|
| `Testing` | Facade: CRUD for TestSuite + TestRequest, security transforms |
| `TestingQueries` | Query builders for suites and requests |
| `TestGenerator` | LLM call + compile-check retry (max 3 retries) |
| `TestRunner` | Executes tests in isolated sandbox (30s timeout, 20MB heap) |
| `TestSuite` | Schema: `test_suites`. One per generation run per API. |
| `TestRequest` | Schema: `test_requests`. One per manual HTTP request from UI. |
| `TestPrompts` | Prompt builders: `system_prompt/0`, `build_generation_prompt/2`, `parse_response/1` |
| `SandboxCase` | Replaces `use ExUnit.Case` in generated tests (prevents ExUnit registration) |
| `ResponseValidator` | Flat schema validation for manual test requests |
| `ContractValidator` | Full OpenAPI contract validation via ExJsonSchema |
| `RequestExecutor` | HTTP execution with SSRF protection (relative paths only) |
| `SampleData` | Generates test payloads from API schema (no LLM) |
| `SnippetGenerator` | Code snippets in 6 languages (curl, python, js, elixir, ruby, go) |

## Sandbox Constraints

| Limit | Default | Hard Cap |
|-------|---------|----------|
| Timeout | 30s | 60s |
| Heap size | 20MB | 50MB |

## Public API (Facade)

```elixir
# TestSuite
create_test_suite(map()) :: {:ok, TestSuite.t()} | {:error, Ecto.Changeset.t()}
update_test_suite(TestSuite.t(), map()) :: {:ok, TestSuite.t()} | {:error, Ecto.Changeset.t()}
list_test_suites(api_id, limit) :: [TestSuite.t()]
get_latest_test_suite(api_id) :: TestSuite.t() | nil

# TestRequest
create_test_request(map()) :: {:ok, TestRequest.t()} | {:error, Ecto.Changeset.t()}
list_test_requests(api_id, limit) :: [TestRequest.t()]
clear_history(api_id) :: {:ok, non_neg_integer()}
```

`create_test_request/1` auto-applies: header redaction (authorization, cookie, x-api-key, etc.) + response body truncation at 65,536 bytes.

## Gotchas

1. **Handler module name collision** — `TestRunner` always compiles handler as `Handler`. Concurrent runs for different APIs overwrite each other. Safe only with single-tenant execution.
2. **Empty test module** — `TestRunner` errors if no `"test "/1` functions found. LLM may generate arity-2 tests that SandboxCase doesn't define.
3. **Module leak on crash** — `purge_modules/1` only runs in success path. Leaked modules persist until node restart.
4. **`ContractValidator` requires decoded body** — body must be a map, not binary. Use `ResponseValidator` for binary bodies.
5. **`RequestExecutor` SSRF guard** — only allows relative paths `^/api/[^/]+/[^/]+`. Any URL with scheme or host is rejected.
