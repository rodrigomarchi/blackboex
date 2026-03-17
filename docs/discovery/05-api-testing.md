# Discovery: API Testing System for LLM-Generated APIs

> **Date**: 2026-03-17
> **Context**: BlackBoex -- platform where users describe APIs in natural language, an LLM generates Elixir code, and users publish it as a REST endpoint.
> **Goal**: Design a comprehensive API testing system that lets users test, debug, validate, and load-test their LLM-generated APIs before and after publishing.

---

## Table of Contents

1. [Interactive API Testing UI](#1-interactive-api-testing-ui)
2. [Auto-Generated Tests](#2-auto-generated-tests)
3. [Request/Response Inspection](#3-requestresponse-inspection)
4. [Mock Data Generation](#4-mock-data-generation)
5. [Load Testing](#5-load-testing)
6. [Contract Testing](#6-contract-testing)
7. [Test Environments / Sandboxes](#7-test-environments--sandboxes)
8. [cURL and Code Snippet Generation](#8-curl-and-code-snippet-generation)
9. [Architecture Recommendation for BlackBoex](#9-architecture-recommendation-for-blackboex)

---

## 1. Interactive API Testing UI

### 1.1 The Problem

Users who describe an API in natural language and get generated code need a way to immediately test the resulting endpoint without leaving the platform. The experience should feel like Postman or Swagger UI but integrated directly into the BlackBoex workflow.

### 1.2 Approach A: Embedded Swagger UI via `open_api_spex`

[open_api_spex](https://github.com/open-api-spex/open_api_spex) (v3.22+ on Hex) is the standard Elixir library for OpenAPI 3.x specifications. It provides:

- **Spec generation** from controller/schema annotations
- **SwaggerUI plug** to serve an interactive explorer
- **Request validation** via `CastAndValidate` plug
- **Response validation** via `TestAssertions`
- **Example data generation** from schemas

**Router setup:**

```elixir
# In the Phoenix router
scope "/api" do
  pipe_through :api

  # User's generated API routes are mounted here dynamically
  # ...

  # Serve the OpenAPI JSON spec
  get "/openapi", OpenApiSpex.Plug.RenderSpec, []
end

scope "/testing" do
  pipe_through :browser

  # Swagger UI pointed at the spec
  get "/swagger/:api_id",
    OpenApiSpex.Plug.SwaggerUI,
    path: "/api/:api_id/openapi"
end
```

**Generating specs dynamically per user API:**

Since BlackBoex generates APIs from LLM output, the OpenAPI spec should also be generated. The LLM can produce both the Elixir implementation and the OpenAPI spec simultaneously, or we can derive the spec from the generated code's `@spec` annotations and schema definitions.

```elixir
defmodule Blackboex.ApiSpec.Builder do
  @moduledoc """
  Builds an OpenAPI spec from a user's API definition.
  """

  @spec build(Blackboex.Api.t()) :: OpenApiSpex.OpenApi.t()
  def build(%Blackboex.Api{} = api) do
    %OpenApiSpex.OpenApi{
      info: %OpenApiSpex.Info{
        title: api.name,
        version: api.version,
        description: api.description
      },
      paths: build_paths(api.endpoints),
      components: %OpenApiSpex.Components{
        schemas: build_schemas(api.schemas)
      }
    }
  end

  defp build_paths(endpoints) do
    # Convert each endpoint definition to an OpenApiSpex.PathItem
    Map.new(endpoints, fn endpoint ->
      {endpoint.path, build_path_item(endpoint)}
    end)
  end

  defp build_path_item(endpoint) do
    # Build operation with parameters, request body, responses
    # ...
  end

  defp build_schemas(schemas) do
    # Convert Ecto schemas or JSON schema defs to OpenApiSpex schemas
    # ...
  end
end
```

**Pros:** Battle-tested, standard OpenAPI tooling, Swagger UI is familiar to developers.
**Cons:** Swagger UI is a separate JS app embedded via iframe/CDN, not deeply integrated into the LiveView UX.

### 1.3 Approach B: Custom LiveView API Playground (Recommended)

Build a Postman-like experience as a native LiveView component. This gives full control over UX and integrates deeply with the rest of BlackBoex (request history, auth, real-time results).

**Core components:**

```elixir
defmodule BlackboexWeb.ApiPlaygroundLive do
  use BlackboexWeb, :live_view

  @impl true
  def mount(%{"api_id" => api_id}, _session, socket) do
    api = Blackboex.Apis.get_api!(api_id)
    spec = Blackboex.ApiSpec.Builder.build(api)

    {:ok,
     assign(socket,
       api: api,
       spec: spec,
       method: "GET",
       path: hd(api.endpoints).path,
       headers: [%{key: "Content-Type", value: "application/json"}],
       body: "",
       query_params: [],
       response: nil,
       response_time: nil,
       status: nil,
       request_history: []
     )}
  end

  @impl true
  def handle_event("send_request", _params, socket) do
    start_time = System.monotonic_time(:millisecond)

    result =
      Blackboex.ApiTester.execute_request(%{
        method: socket.assigns.method,
        path: socket.assigns.path,
        headers: socket.assigns.headers,
        body: socket.assigns.body,
        query_params: socket.assigns.query_params,
        api_id: socket.assigns.api.id
      })

    elapsed = System.monotonic_time(:millisecond) - start_time

    history_entry = %{
      method: socket.assigns.method,
      path: socket.assigns.path,
      status: result.status,
      time: elapsed,
      timestamp: DateTime.utc_now()
    }

    {:noreply,
     assign(socket,
       response: result.body,
       response_time: elapsed,
       status: result.status,
       response_headers: result.headers,
       request_history: [history_entry | socket.assigns.request_history]
     )}
  end

  @impl true
  def handle_event("update_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, method: method)}
  end

  @impl true
  def handle_event("update_body", %{"body" => body}, socket) do
    {:noreply, assign(socket, body: body)}
  end
end
```

**LiveView template structure (using SaladUI components):**

```heex
<div class="flex h-full">
  <!-- Left panel: Request builder -->
  <div class="w-1/2 border-r p-4 flex flex-col gap-4">
    <!-- Method + URL bar -->
    <div class="flex gap-2">
      <.select name="method" value={@method} phx-change="update_method">
        <option value="GET">GET</option>
        <option value="POST">POST</option>
        <option value="PUT">PUT</option>
        <option value="PATCH">PATCH</option>
        <option value="DELETE">DELETE</option>
      </.select>
      <.input type="text" name="path" value={@path} class="flex-1" />
      <.button phx-click="send_request" variant="default">
        Send
      </.button>
    </div>

    <!-- Tabs: Params | Headers | Body | Auth -->
    <.tabs default="body">
      <.tabs_list>
        <.tabs_trigger value="params">Query Params</.tabs_trigger>
        <.tabs_trigger value="headers">Headers</.tabs_trigger>
        <.tabs_trigger value="body">Body</.tabs_trigger>
        <.tabs_trigger value="auth">Auth</.tabs_trigger>
      </.tabs_list>

      <.tabs_content value="params">
        <.key_value_editor entries={@query_params} target="query_params" />
      </.tabs_content>

      <.tabs_content value="headers">
        <.key_value_editor entries={@headers} target="headers" />
      </.tabs_content>

      <.tabs_content value="body">
        <.code_editor value={@body} language="json" phx-change="update_body" />
      </.tabs_content>
    </.tabs>
  </div>

  <!-- Right panel: Response viewer -->
  <div class="w-1/2 p-4 flex flex-col gap-4">
    <div :if={@status} class="flex items-center gap-4">
      <.badge variant={status_variant(@status)}>
        {@status}
      </.badge>
      <span class="text-sm text-muted-foreground">
        {@response_time}ms
      </span>
    </div>

    <!-- Tabs: Body | Headers | Validation -->
    <.tabs default="response_body">
      <.tabs_content value="response_body">
        <.code_viewer value={@response} language="json" />
      </.tabs_content>

      <.tabs_content value="response_headers">
        <.header_table headers={@response_headers} />
      </.tabs_content>

      <.tabs_content value="validation">
        <.contract_validation response={@response} spec={@spec} />
      </.tabs_content>
    </.tabs>
  </div>
</div>
```

### 1.4 UX Recommendations

1. **Auto-populate from spec** -- When a user selects an endpoint, pre-fill the path, method, required headers, and example body from the OpenAPI spec.
2. **Real-time validation** -- As the user types the request body, validate against the schema and show inline errors.
3. **One-click test** -- After code generation completes, show a "Test Now" button that opens the playground pre-configured for the first endpoint.
4. **Response diff** -- When re-running a request, show what changed vs. the previous response.
5. **Keyboard shortcuts** -- Ctrl+Enter to send request, Ctrl+L to clear, familiar to Postman users.

### 1.5 Hybrid Approach

Serve Swagger UI at `/api/:api_id/docs` for users who prefer the standard tool, and the custom LiveView playground at `/api/:api_id/test` for the integrated experience. Both consume the same OpenAPI spec.

---

## 2. Auto-Generated Tests

### 2.1 The Problem

When the LLM generates an API, it should also generate tests to verify the API works correctly. This creates a feedback loop: the user can see the tests pass, gain confidence, and catch regressions.

### 2.2 LLM-Generated Test Strategy

Since BlackBoex already uses an LLM to generate the API code, the same (or a follow-up) LLM call should generate ExUnit tests. The prompt should request:

1. **Happy path tests** -- One test per endpoint with valid input
2. **Validation tests** -- Tests with missing/invalid fields
3. **Edge case tests** -- Empty strings, boundary values, large payloads
4. **Error response tests** -- Expected error codes and messages

**Prompt template for test generation:**

```text
You are generating ExUnit tests for an Elixir Phoenix API.

## API Specification
{openapi_spec_json}

## Implementation Code
{generated_elixir_code}

## Requirements
- Generate ExUnit tests using Phoenix.ConnTest
- Each endpoint must have at least:
  - 1 happy-path test (valid input -> expected output)
  - 1 validation test (invalid input -> 422)
  - 1 not-found test (if applicable -> 404)
- Use @tag :generated for all tests
- Use descriptive test names
- Assert on status codes, response body structure, and content-type headers
- Use Jason.decode!/1 for JSON parsing
- Do NOT use any external dependencies beyond ExUnit and Phoenix.ConnTest

## Output
Return ONLY the ExUnit test module code, no explanations.
```

**Example generated test:**

```elixir
defmodule BlackboexWeb.Generated.TodoApiTest do
  use BlackboexWeb.ConnCase, async: true

  @tag :generated
  @tag :integration
  describe "POST /api/todos" do
    test "creates a todo with valid params", %{conn: conn} do
      params = %{"title" => "Buy milk", "completed" => false}

      conn = post(conn, "/api/v1/todos", params)

      assert %{"id" => id, "title" => "Buy milk", "completed" => false} =
               json_response(conn, 201)

      assert is_integer(id)
    end

    test "returns 422 with missing title", %{conn: conn} do
      params = %{"completed" => false}

      conn = post(conn, "/api/v1/todos", params)

      assert %{"errors" => %{"title" => ["can't be blank"]}} =
               json_response(conn, 422)
    end
  end

  @tag :generated
  describe "GET /api/todos" do
    test "returns empty list when no todos exist", %{conn: conn} do
      conn = get(conn, "/api/v1/todos")

      assert json_response(conn, 200) == []
    end
  end
end
```

### 2.3 Meta's TestGen-LLM Insights

[Meta's research on TestGen-LLM](https://arxiv.org/abs/2402.09171) shows that LLM-generated tests can be effective:

- 75% of generated tests compile successfully
- 57% pass reliably
- 25% increase code coverage
- 73% acceptance rate by human reviewers

Their approach uses iterative refinement: generate, compile, run, fix failures, repeat. BlackBoex should adopt the same pattern.

**Implementation: iterative test generation pipeline:**

```elixir
defmodule Blackboex.TestGenerator do
  @moduledoc """
  Generates and validates ExUnit tests for user APIs using LLM.
  """

  @max_retries 3

  @spec generate_and_validate(Blackboex.Api.t()) ::
          {:ok, [Blackboex.GeneratedTest.t()]} | {:error, term()}
  def generate_and_validate(api) do
    with {:ok, spec} <- Blackboex.ApiSpec.Builder.build(api),
         {:ok, test_code} <- generate_tests(api, spec),
         {:ok, compiled} <- compile_tests(test_code),
         {:ok, results} <- run_tests(compiled) do
      {:ok, results}
    else
      {:error, :compilation_failed, errors} ->
        refine_tests(api, test_code, errors, @max_retries)

      {:error, :tests_failed, failures} ->
        {:ok, mark_failures(failures)}

      error ->
        error
    end
  end

  defp generate_tests(api, spec) do
    prompt = build_test_prompt(api, spec)
    Blackboex.LLM.complete(prompt, model: :default)
  end

  defp compile_tests(test_code) do
    # Compile in a temporary module namespace to avoid conflicts
    # Use Code.compile_string/2 with a unique module name
    try do
      Code.compile_string(test_code)
      {:ok, test_code}
    rescue
      e in CompileError ->
        {:error, :compilation_failed, Exception.message(e)}
    end
  end

  defp run_tests(test_code) do
    # Execute tests using ExUnit programmatic API
    # Capture results and return structured output
    # ...
  end

  defp refine_tests(_api, _test_code, _errors, 0),
    do: {:error, :max_retries_exceeded}

  defp refine_tests(api, test_code, errors, retries) do
    prompt = """
    The following ExUnit tests have compilation errors.
    Fix the errors and return the corrected test code.

    ## Test Code
    #{test_code}

    ## Errors
    #{errors}
    """

    with {:ok, fixed_code} <- Blackboex.LLM.complete(prompt),
         {:ok, compiled} <- compile_tests(fixed_code),
         {:ok, results} <- run_tests(compiled) do
      {:ok, results}
    else
      {:error, :compilation_failed, new_errors} ->
        refine_tests(api, fixed_code, new_errors, retries - 1)

      other ->
        other
    end
  end
end
```

### 2.4 Property-Based Testing with StreamData

[StreamData](https://github.com/whatyouhide/stream_data) (v1.3.0 on Hex) enables property-based testing for Elixir. For API testing, it generates random but structured input to find edge cases.

**How to integrate with BlackBoex:**

The LLM can generate StreamData generators based on the API's schema, then property tests verify invariants like "valid input always returns 2xx" or "the response always matches the schema."

```elixir
defmodule BlackboexWeb.Generated.TodoApiPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Generator derived from the OpenAPI schema
  defp todo_params_gen do
    gen all(
          title <- string(:alphanumeric, min_length: 1, max_length: 255),
          completed <- boolean()
        ) do
      %{"title" => title, "completed" => completed}
    end
  end

  property "POST /api/todos always returns 201 with valid params" do
    check all(params <- todo_params_gen()) do
      conn = build_conn() |> post("/api/v1/todos", params)
      assert conn.status == 201
      assert %{"id" => _, "title" => _, "completed" => _} = json_response(conn, 201)
    end
  end

  property "response title always matches input title" do
    check all(params <- todo_params_gen()) do
      conn = build_conn() |> post("/api/v1/todos", params)
      response = json_response(conn, 201)
      assert response["title"] == params["title"]
    end
  end
end
```

**BlackBoex can auto-generate StreamData generators from OpenAPI schemas:**

```elixir
defmodule Blackboex.TestGenerator.StreamDataBuilder do
  @moduledoc """
  Generates StreamData generators from OpenAPI schema definitions.
  """

  @spec schema_to_generator(OpenApiSpex.Schema.t()) :: String.t()
  def schema_to_generator(%OpenApiSpex.Schema{type: :string} = schema) do
    min = schema.minLength || 0
    max = schema.maxLength || 255

    if schema.enum do
      "member_of(#{inspect(schema.enum)})"
    else
      "string(:alphanumeric, min_length: #{min}, max_length: #{max})"
    end
  end

  def schema_to_generator(%OpenApiSpex.Schema{type: :integer} = schema) do
    min = schema.minimum || -1_000_000
    max = schema.maximum || 1_000_000
    "integer(#{min}..#{max})"
  end

  def schema_to_generator(%OpenApiSpex.Schema{type: :boolean}) do
    "boolean()"
  end

  def schema_to_generator(%OpenApiSpex.Schema{type: :object, properties: props}) do
    fields =
      Enum.map_join(props, ",\n      ", fn {name, schema} ->
        "#{name} <- #{schema_to_generator(schema)}"
      end)

    map_fields =
      Enum.map_join(props, ", ", fn {name, _} ->
        ~s("#{name}" => #{name})
      end)

    """
    gen all(
      #{fields}
    ) do
      %{#{map_fields}}
    end
    """
  end
end
```

### 2.5 Displaying Test Results in the UI

Show test results in a dashboard panel alongside the generated code:

- Green/red indicators per test
- Click to expand: see the assertion, expected vs actual
- "Re-run tests" button
- "Regenerate failing tests" button (triggers another LLM call)
- Coverage percentage (if measurable)

---

## 3. Request/Response Inspection

### 3.1 The Problem

Users need full visibility into what their API receives and returns -- headers, body, timing, errors -- to debug issues in LLM-generated code.

### 3.2 Telemetry-Based Request Recording

Phoenix emits [Telemetry events](https://hexdocs.pm/phoenix/telemetry.html) at every stage of request processing. BlackBoex should attach handlers to capture full request/response pairs.

**Key telemetry events:**

| Event | When | Metadata |
|---|---|---|
| `[:phoenix, :endpoint, :start]` | Request arrives | `%{conn: conn}` |
| `[:phoenix, :endpoint, :stop]` | Response sent | `%{conn: conn, duration: ns}` |
| `[:phoenix, :router_dispatch, :start]` | Route matched | `%{conn: conn, route: path}` |
| `[:phoenix, :router_dispatch, :stop]` | Controller done | `%{conn: conn, duration: ns}` |
| `[:blackboex, :generated_api, :call]` | Custom: LLM code executed | `%{api_id: id, input: map}` |

**Implementation: request recorder plug + telemetry handler:**

```elixir
defmodule BlackboexWeb.Plugs.RequestRecorder do
  @moduledoc """
  Plug that captures the full request body before parsing
  and stores it for later inspection.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    # Read and cache the raw body (Plug.Parsers consumes it)
    {:ok, raw_body, conn} = Plug.Conn.read_body(conn)

    conn
    |> Plug.Conn.put_private(:raw_request_body, raw_body)
    |> Plug.Conn.put_private(:request_started_at, System.monotonic_time(:microsecond))
  end
end
```

```elixir
defmodule Blackboex.RequestInspector do
  @moduledoc """
  Telemetry handler that records request/response pairs
  for user-generated APIs.
  """

  require Logger

  @spec attach() :: :ok
  def attach do
    :telemetry.attach(
      "blackboex-request-inspector",
      [:phoenix, :endpoint, :stop],
      &__MODULE__.handle_event/4,
      %{}
    )
  end

  @spec handle_event(list(), map(), map(), map()) :: :ok
  def handle_event(
        [:phoenix, :endpoint, :stop],
        %{duration: duration},
        %{conn: conn},
        _config
      ) do
    # Only record for generated API routes
    if generated_api_request?(conn) do
      record = %{
        api_id: conn.private[:api_id],
        user_id: conn.assigns[:current_user]&.id,
        method: conn.method,
        path: conn.request_path,
        query_string: conn.query_string,
        request_headers: redact_sensitive(conn.req_headers),
        request_body: conn.private[:raw_request_body],
        response_status: conn.status,
        response_headers: conn.resp_headers,
        response_body: conn.resp_body,
        duration_us: System.convert_time_unit(duration, :native, :microsecond),
        timestamp: DateTime.utc_now()
      }

      Blackboex.RequestLog.create(record)
    end

    :ok
  end

  defp generated_api_request?(conn) do
    Map.has_key?(conn.private, :api_id)
  end

  defp redact_sensitive(headers) do
    Enum.map(headers, fn
      {"authorization", _} -> {"authorization", "[REDACTED]"}
      {"cookie", _} -> {"cookie", "[REDACTED]"}
      header -> header
    end)
  end
end
```

### 3.3 Request Log Schema

```elixir
defmodule Blackboex.RequestLog.Entry do
  use Ecto.Schema

  schema "request_log_entries" do
    belongs_to :api, Blackboex.Api
    belongs_to :user, Blackboex.Accounts.User

    field :method, :string
    field :path, :string
    field :query_string, :string
    field :request_headers, :map
    field :request_body, :string
    field :response_status, :integer
    field :response_headers, :map
    field :response_body, :string
    field :duration_us, :integer

    timestamps(type: :utc_datetime_usec)
  end
end
```

**Migration:**

```elixir
defmodule Blackboex.Repo.Migrations.CreateRequestLogEntries do
  use Ecto.Migration

  def change do
    create table(:request_log_entries) do
      add :api_id, references(:apis, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :method, :string, null: false
      add :path, :string, null: false
      add :query_string, :text
      add :request_headers, :map, default: %{}
      add :request_body, :text
      add :response_status, :integer
      add :response_headers, :map, default: %{}
      add :response_body, :text
      add :duration_us, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:request_log_entries, [:api_id])
    create index(:request_log_entries, [:user_id])
    create index(:request_log_entries, [:inserted_at])
  end
end
```

### 3.4 Retention and Performance

- **TTL-based cleanup**: Use a periodic `Oban` job to delete entries older than 7 days (free tier) or 30 days (paid).
- **Size limits**: Truncate `request_body` and `response_body` at 64KB. Store full bodies in S3 if needed.
- **Sampling**: Under high load, record a configurable percentage (e.g., 10%) instead of all requests.
- **Async writes**: Use `Task.Supervisor.async_nolink/2` or Oban to avoid blocking the request path.

### 3.5 UI for Request Inspection

Display a timeline/table of recent requests with:

- Status badge (green 2xx, yellow 3xx, red 4xx/5xx)
- Method, path, duration
- Click to expand: full headers, body (syntax-highlighted JSON), timing breakdown
- Replay button: re-send the exact same request
- Filter by status, method, time range
- Real-time updates via LiveView (new requests appear as they happen using PubSub)

---

## 4. Mock Data Generation

### 4.1 The Problem

Generated APIs often need sample data to be useful for testing. Users should not have to manually create test payloads.

### 4.2 Libraries

| Library | Purpose | Hex Downloads | Notes |
|---|---|---|---|
| [Faker](https://hex.pm/packages/faker) | Realistic fake data (names, emails, addresses, etc.) | Very high | Elixir port of Ruby Faker |
| [ExMachina](https://hex.pm/packages/ex_machina) | Test factories with Ecto integration | Very high | ThoughtBot, `build/insert` pattern |
| [StreamData](https://hex.pm/packages/stream_data) | Random data generators for property tests | High | Composable generators |

### 4.3 Auto-Generated Sample Data from Schema

When the LLM generates an API with a schema, BlackBoex should also generate realistic sample data. Two approaches:

**Approach A: Schema-driven Faker (compile-time):**

```elixir
defmodule Blackboex.MockData.Generator do
  @moduledoc """
  Generates mock data from OpenAPI schemas using Faker.
  """

  @spec generate(OpenApiSpex.Schema.t()) :: map()
  def generate(%OpenApiSpex.Schema{type: :object, properties: props}) do
    Map.new(props, fn {name, schema} ->
      {Atom.to_string(name), generate_value(name, schema)}
    end)
  end

  @spec generate_value(atom(), OpenApiSpex.Schema.t()) :: term()
  defp generate_value(name, %{type: :string} = schema) do
    cond do
      schema.format == "email" -> Faker.Internet.email()
      schema.format == "uri" -> Faker.Internet.url()
      schema.format == "date-time" -> DateTime.utc_now() |> DateTime.to_iso8601()
      schema.format == "date" -> Date.utc_today() |> Date.to_iso8601()
      schema.format == "uuid" -> Ecto.UUID.generate()
      name_suggests_email?(name) -> Faker.Internet.email()
      name_suggests_name?(name) -> Faker.Person.name()
      name_suggests_phone?(name) -> Faker.Phone.EnUs.phone()
      name_suggests_address?(name) -> Faker.Address.street_address()
      schema.enum -> Enum.random(schema.enum)
      true -> Faker.Lorem.sentence(3)
    end
  end

  defp generate_value(_name, %{type: :integer} = schema) do
    min = schema.minimum || 1
    max = schema.maximum || 1000
    Enum.random(min..max)
  end

  defp generate_value(_name, %{type: :number}) do
    :rand.uniform() * 1000 |> Float.round(2)
  end

  defp generate_value(_name, %{type: :boolean}) do
    Enum.random([true, false])
  end

  defp generate_value(_name, %{type: :array, items: item_schema}) do
    count = Enum.random(1..5)
    Enum.map(1..count, fn _ -> generate(item_schema) end)
  end

  defp name_suggests_email?(name) do
    name_str = Atom.to_string(name)
    String.contains?(name_str, "email")
  end

  defp name_suggests_name?(name) do
    name_str = Atom.to_string(name)
    name_str in ~w(name first_name last_name full_name username)
  end

  defp name_suggests_phone?(name) do
    name_str = Atom.to_string(name)
    String.contains?(name_str, "phone") or String.contains?(name_str, "tel")
  end

  defp name_suggests_address?(name) do
    name_str = Atom.to_string(name)
    String.contains?(name_str, "address") or String.contains?(name_str, "street")
  end
end
```

**Approach B: LLM-generated realistic data:**

Include a prompt step that asks the LLM to generate 5-10 realistic sample records that make sense in context. A todo API gets todos that sound real, a user API gets plausible user profiles.

**Approach C: OpenApiSpex built-in example generation:**

`open_api_spex` can generate example data from schemas:

```elixir
# OpenApiSpex already generates example data for SwaggerUI
# We can tap into the same mechanism
example = OpenApiSpex.Schema.example(schema)
```

### 4.4 UX: "Fill with Sample Data" Button

In the API playground, add a "Fill with Sample Data" button that:

1. Reads the schema for the selected endpoint's request body
2. Generates realistic data using the approach above
3. Populates the request body editor
4. User can tweak before sending

Also provide a "Generate N records" feature that bulk-creates test data in the API's database.

---

## 5. Load Testing

### 5.1 The Problem

Users want to know if their generated API can handle real-world traffic before publishing. Basic load testing gives confidence.

### 5.2 Elixir-Native: Chaperon

[Chaperon](https://github.com/polleverywhere/chaperon) (v0.3.1 on Hex) is an Elixir HTTP load testing framework. Key features:

- Written in Elixir, leverages BEAM concurrency
- Supports HTTP and WebSocket protocols
- Distributed load testing across Erlang nodes
- Session-based scenario definitions
- Has been used to simulate 100k+ concurrent sessions

**Example Chaperon scenario for a generated API:**

```elixir
defmodule Blackboex.LoadTest.ApiScenario do
  use Chaperon.Scenario

  def init(session) do
    session
    |> assign(base_url: session.config[:base_url])
    |> assign(api_path: session.config[:api_path])
  end

  def run(session) do
    session
    |> get(session.assigned.api_path)
    |> verify_status(200)
    |> delay(:timer.seconds(1))
    |> post(session.assigned.api_path,
      json: %{
        "title" => "Load test item #{:rand.uniform(10000)}",
        "completed" => false
      }
    )
    |> verify_status(201)
  end
end
```

```elixir
defmodule Blackboex.LoadTest.ApiLoadTest do
  use Chaperon.LoadTest

  def default_config do
    %{
      base_url: "http://localhost:4000"
    }
  end

  def scenarios do
    [
      {Blackboex.LoadTest.ApiScenario,
       %{
         api_path: "/api/v1/todos",
         concurrency: 50,
         duration: :timer.seconds(30)
       }}
    ]
  end
end
```

### 5.3 External: k6 Integration

[k6](https://k6.io/) is a modern load testing tool. The [elixir-k6](https://github.com/besughi/elixir-k6) library provides an Elixir wrapper:

- Generates k6 scripts from Elixir definitions
- Supports REST, GraphQL, gRPC, WebSocket, Phoenix channels, and LiveView (experimental)
- Requires k6 installed locally or in CI

**Example k6 integration:**

```elixir
# mix.exs
{:elixir_k6, "~> 0.1", only: [:dev, :test]}
```

**Generated k6 script template:**

```javascript
// Auto-generated by BlackBoex for API: {{api_name}}
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp up
    { duration: '1m', target: 10 },    // Sustain
    { duration: '10s', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% under 500ms
    http_req_failed: ['rate<0.01'],    // <1% errors
  },
};

export default function () {
  const baseUrl = '{{base_url}}';

  // GET endpoint
  const getRes = http.get(`${baseUrl}{{get_path}}`);
  check(getRes, {
    'GET status is 200': (r) => r.status === 200,
    'GET response time < 200ms': (r) => r.timings.duration < 200,
  });

  // POST endpoint
  const payload = JSON.stringify({{example_body}});
  const postRes = http.post(`${baseUrl}{{post_path}}`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });
  check(postRes, {
    'POST status is 201': (r) => r.status === 201,
  });

  sleep(1);
}
```

### 5.4 Benchee for Micro-Benchmarks

[Benchee](https://github.com/bencheeorg/benchee) is useful for benchmarking individual functions rather than full HTTP endpoints. Useful for measuring the performance of the generated Elixir code itself:

```elixir
Benchee.run(%{
  "create_todo" => fn ->
    Blackboex.Generated.TodoApi.create(%{"title" => "test", "completed" => false})
  end,
  "list_todos" => fn ->
    Blackboex.Generated.TodoApi.list()
  end
})
```

### 5.5 BlackBoex Load Test Feature Design

For the platform, offer a simplified load test that users trigger from the UI:

1. **Quick test** -- 10 concurrent users for 30 seconds (free tier)
2. **Standard test** -- 50 concurrent users for 2 minutes
3. **Custom test** -- User configures concurrency, duration, ramp-up

**Results dashboard shows:**

- Requests per second (RPS)
- Latency percentiles (p50, p95, p99)
- Error rate
- Throughput chart over time (LiveView real-time updates via PubSub)
- Pass/fail against thresholds (e.g., "p95 < 500ms")

**Implementation: run load tests as supervised tasks:**

```elixir
defmodule Blackboex.LoadTest.Runner do
  @moduledoc """
  Orchestrates load tests for user APIs.
  Runs as a supervised task with resource limits.
  """

  @spec run(Blackboex.Api.t(), keyword()) :: {:ok, Blackboex.LoadTest.Result.t()}
  def run(api, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 10)
    duration_ms = Keyword.get(opts, :duration_ms, 30_000)
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")

    # Broadcast start
    Phoenix.PubSub.broadcast(
      Blackboex.PubSub,
      "load_test:#{api.id}",
      {:load_test_started, %{concurrency: concurrency, duration_ms: duration_ms}}
    )

    results =
      1..concurrency
      |> Task.async_stream(
        fn worker_id ->
          run_worker(api, base_url, duration_ms, worker_id)
        end,
        max_concurrency: concurrency,
        timeout: duration_ms + 10_000
      )
      |> Enum.flat_map(fn {:ok, requests} -> requests end)

    summary = calculate_summary(results)

    Phoenix.PubSub.broadcast(
      Blackboex.PubSub,
      "load_test:#{api.id}",
      {:load_test_completed, summary}
    )

    {:ok, summary}
  end

  defp run_worker(api, base_url, duration_ms, _worker_id) do
    deadline = System.monotonic_time(:millisecond) + duration_ms
    run_until(api, base_url, deadline, [])
  end

  defp run_until(api, base_url, deadline, acc) do
    if System.monotonic_time(:millisecond) >= deadline do
      acc
    else
      result = execute_single_request(api, base_url)
      run_until(api, base_url, deadline, [result | acc])
    end
  end

  defp execute_single_request(api, base_url) do
    endpoint = Enum.random(api.endpoints)
    start = System.monotonic_time(:microsecond)

    response =
      Req.request(
        method: String.to_atom(String.downcase(endpoint.method)),
        url: base_url <> endpoint.path,
        json: endpoint.example_body
      )

    elapsed = System.monotonic_time(:microsecond) - start

    %{
      status: elem(response, 1).status,
      duration_us: elapsed,
      method: endpoint.method,
      path: endpoint.path,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp calculate_summary(results) do
    durations = Enum.map(results, & &1.duration_us) |> Enum.sort()
    total = length(results)
    errors = Enum.count(results, fn r -> r.status >= 400 end)

    %{
      total_requests: total,
      error_count: errors,
      error_rate: if(total > 0, do: errors / total, else: 0),
      p50_us: percentile(durations, 50),
      p95_us: percentile(durations, 95),
      p99_us: percentile(durations, 99),
      min_us: List.first(durations),
      max_us: List.last(durations),
      avg_us: if(total > 0, do: Enum.sum(durations) / total, else: 0),
      requests_per_second: total / (List.last(durations) - List.first(durations)) * 1_000_000
    }
  end

  defp percentile(sorted_list, p) do
    index = ceil(length(sorted_list) * p / 100) - 1
    Enum.at(sorted_list, max(index, 0))
  end
end
```

### 5.6 Safety Guardrails

- **Rate limit** load tests per user (e.g., 1 concurrent test, max 5 per hour)
- **Resource isolation**: Run load tests against a separate process group or node to avoid impacting other users
- **Hard timeout**: Kill load tests exceeding their duration + grace period
- **Target self only**: Only allow load testing of the user's own APIs, never external targets

---

## 6. Contract Testing

### 6.1 The Problem

The generated API should conform to its specification. Contract testing validates that the actual responses match the declared OpenAPI schema.

### 6.2 OpenApiSpex TestAssertions

`open_api_spex` provides the `OpenApiSpex.TestAssertions` module for contract validation in tests:

```elixir
defmodule BlackboexWeb.ContractTest do
  use BlackboexWeb.ConnCase, async: true

  import OpenApiSpex.TestAssertions

  @tag :contract
  test "GET /api/todos conforms to spec", %{conn: conn} do
    spec = BlackboexWeb.ApiSpec.spec()

    conn = get(conn, "/api/v1/todos")

    assert_schema(json_response(conn, 200), "TodoList", spec)
  end

  @tag :contract
  test "POST /api/todos request and response conform to spec", %{conn: conn} do
    spec = BlackboexWeb.ApiSpec.spec()
    params = %{"title" => "Test", "completed" => false}

    conn = post(conn, "/api/v1/todos", params)

    assert_schema(json_response(conn, 201), "Todo", spec)
  end
end
```

### 6.3 Runtime Contract Validation

Beyond tests, validate every response at runtime (in dev/staging) using a plug:

```elixir
defmodule BlackboexWeb.Plugs.ContractValidator do
  @moduledoc """
  Validates API responses against the OpenAPI spec at runtime.
  Only active in dev/test environments.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Plug.Conn.register_before_send(conn, fn conn ->
      if generated_api_request?(conn) do
        validate_response(conn)
      else
        conn
      end
    end)
  end

  defp validate_response(conn) do
    api_id = conn.private[:api_id]
    spec = Blackboex.ApiSpec.Cache.get(api_id)

    case validate_against_spec(conn, spec) do
      :ok ->
        conn

      {:error, errors} ->
        # Log the contract violation but don't block the response
        Logger.warning("Contract violation for API #{api_id}: #{inspect(errors)}")

        # Store violations for the UI to display
        Blackboex.ContractViolations.record(api_id, %{
          path: conn.request_path,
          method: conn.method,
          status: conn.status,
          errors: errors,
          timestamp: DateTime.utc_now()
        })

        conn
    end
  end

  defp validate_against_spec(conn, spec) do
    # Use OpenApiSpex or ex_json_schema to validate
    # the response body against the declared schema
    response_body = Jason.decode!(conn.resp_body)
    operation = find_operation(spec, conn.method, conn.request_path)
    response_schema = get_response_schema(operation, conn.status)

    case ExJsonSchema.Validator.validate(response_schema, response_body) do
      :ok -> :ok
      {:error, errors} -> {:error, errors}
    end
  end
end
```

### 6.4 JSON Schema Validation with ex_json_schema

[ex_json_schema](https://github.com/jonasschmidt/ex_json_schema) supports JSON Schema draft 4, 6, and 7. It passes the official JSON Schema Test Suite:

```elixir
# Resolve and validate
schema = ExJsonSchema.Schema.resolve(%{
  "type" => "object",
  "required" => ["title"],
  "properties" => %{
    "title" => %{"type" => "string", "minLength" => 1},
    "completed" => %{"type" => "boolean"}
  }
})

ExJsonSchema.Validator.validate(schema, %{"title" => "Test", "completed" => false})
# => :ok

ExJsonSchema.Validator.validate(schema, %{"completed" => "not a boolean"})
# => {:error, [{"Type mismatch. Expected Boolean but got String.", "#/completed"}]}
```

### 6.5 Contract Test Dashboard

In the UI, show a "Contract Health" panel:

- Per-endpoint compliance percentage
- Recent violations with details
- "Run full contract suite" button
- Historical trend chart (contract compliance over time)

---

## 7. Test Environments / Sandboxes

### 7.1 The Problem

Each user's API needs an isolated environment where testing does not affect other users or production data. LLM-generated code running on the platform must be sandboxed for security.

### 7.2 Database Isolation with Ecto Sandbox

Ecto provides `Ecto.Adapters.SQL.Sandbox` for test isolation. Each test (or user session) gets its own database transaction that is rolled back at the end.

**For BlackBoex testing mode:**

```elixir
defmodule Blackboex.TestEnvironment do
  @moduledoc """
  Manages isolated test environments for user API testing.
  Each environment gets a sandboxed database connection.
  """

  @spec create(Blackboex.Api.t()) :: {:ok, pid()} | {:error, term()}
  def create(api) do
    # Check out a sandboxed connection
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Blackboex.Repo)

    # Set shared mode so the API handler process can use this connection
    Ecto.Adapters.SQL.Sandbox.mode(Blackboex.Repo, {:shared, self()})

    # Seed the database with the API's schema migrations
    run_api_migrations(api)

    # Optionally seed with mock data
    seed_mock_data(api)

    {:ok, self()}
  end

  @spec destroy(pid()) :: :ok
  def destroy(pid) do
    # The sandbox automatically rolls back when the owning process exits
    Process.exit(pid, :normal)
    :ok
  end

  defp run_api_migrations(api) do
    # Apply any Ecto migrations generated for this API's data model
    Enum.each(api.migrations, fn migration_module ->
      Ecto.Migrator.up(Blackboex.Repo, migration_module.version(), migration_module)
    end)
  end

  defp seed_mock_data(api) do
    mock_data = Blackboex.MockData.Generator.generate_batch(api.schema, count: 10)

    Enum.each(mock_data, fn data ->
      Blackboex.Repo.insert(struct(api.ecto_schema_module, data))
    end)
  end
end
```

### 7.3 Schema-Per-Tenant Isolation (Production)

For stronger isolation, use PostgreSQL schemas (namespaces):

```elixir
defmodule Blackboex.TenantSandbox do
  @moduledoc """
  Creates a PostgreSQL schema per API for full data isolation.
  """

  @spec create_schema(String.t()) :: :ok
  def create_schema(api_id) do
    schema_name = "api_#{api_id}"
    Ecto.Adapters.SQL.query!(Blackboex.Repo, "CREATE SCHEMA IF NOT EXISTS #{schema_name}")
    :ok
  end

  @spec with_schema(String.t(), (-> result)) :: result when result: term()
  def with_schema(api_id, fun) do
    schema_name = "api_#{api_id}"
    Blackboex.Repo.put_dynamic_repo(schema_name)

    try do
      Ecto.Adapters.SQL.query!(Blackboex.Repo, "SET search_path TO #{schema_name}, public")
      fun.()
    after
      Ecto.Adapters.SQL.query!(Blackboex.Repo, "SET search_path TO public")
    end
  end

  @spec drop_schema(String.t()) :: :ok
  def drop_schema(api_id) do
    schema_name = "api_#{api_id}"
    Ecto.Adapters.SQL.query!(Blackboex.Repo, "DROP SCHEMA IF EXISTS #{schema_name} CASCADE")
    :ok
  end
end
```

### 7.4 Code Execution Sandboxing with Dune

[Dune](https://github.com/functional-rewire/dune) is a sandbox for safely evaluating untrusted Elixir code. Since BlackBoex executes LLM-generated code, this is critical for security:

```elixir
# Dune restricts access to dangerous modules/functions
Dune.eval_string("1 + 1")
# => {:ok, 2}

Dune.eval_string("File.read!(\"/etc/passwd\")")
# => {:error, :restricted}

Dune.eval_string("System.cmd(\"rm\", [\"-rf\", \"/\"])")
# => {:error, :restricted}
```

**Dune's allowlist approach:**

- No access to `File`, `System`, `Port`, `Process` (dangerous modules)
- No access to `:os`, `:erlang.open_port` (Erlang escape hatches)
- No network access unless explicitly allowed
- Configurable module allowlists
- Memory and execution time limits

**Alternative: Exbox:**

[Exbox](https://github.com/christhekeele/exbox) takes a different approach -- it rewrites the AST to namespace all function calls through a proxy module:

```elixir
Exbox.eval("String.upcase(\"hello\")", sandbox: MySandbox)
# Only succeeds if MySandbox proxies String.upcase
```

### 7.5 Recommended Isolation Architecture

For BlackBoex, use a layered approach:

| Layer | Mechanism | Purpose |
|---|---|---|
| **Code execution** | Dune sandbox + module allowlist | Prevent LLM-generated code from accessing system resources |
| **Database** | PostgreSQL schemas per API | Data isolation between APIs |
| **Testing** | Ecto.Adapters.SQL.Sandbox | Transaction-based rollback for test runs |
| **Resources** | Process limits + timeouts | Prevent runaway code from consuming CPU/memory |
| **Network** | No outbound access from sandboxed code | Prevent data exfiltration |

```elixir
defmodule Blackboex.Sandbox do
  @moduledoc """
  Unified sandbox that combines code execution, database,
  and resource isolation.
  """

  @allowed_modules [
    Enum, Map, List, String, Integer, Float, Keyword,
    Jason, DateTime, Date, Time, NaiveDateTime,
    Ecto.Query, Ecto.Changeset
  ]

  @spec execute(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute(code, opts \\ []) do
    api_id = Keyword.fetch!(opts, :api_id)
    timeout = Keyword.get(opts, :timeout, 5_000)

    task =
      Task.Supervisor.async_nolink(Blackboex.TaskSupervisor, fn ->
        # Set up database isolation
        TenantSandbox.with_schema(api_id, fn ->
          # Execute in Dune sandbox with module restrictions
          Dune.eval_string(code,
            allowlist: @allowed_modules,
            max_heap_size: 50_000_000,
            timeout: timeout
          )
        end)
      end)

    case Task.yield(task, timeout + 1_000) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, {:crashed, reason}}
    end
  end
end
```

### 7.6 Environment Lifecycle

```text
User clicks "Test API"
       |
       v
  Create sandbox environment
  - PostgreSQL schema created (or Ecto Sandbox checkout)
  - Dune sandbox configured with API's allowed modules
  - Mock data seeded
       |
       v
  User runs tests / sends requests
  - All DB operations scoped to the API's schema
  - Code execution sandboxed via Dune
  - Request/response pairs recorded
       |
       v
  User finishes testing
  - Ecto Sandbox rolled back OR
  - PostgreSQL schema dropped (for cleanup)
  - Request logs retained per retention policy
```

---

## 8. cURL and Code Snippet Generation

### 8.1 The Problem

Users want to test their APIs from the command line or integrate them into applications. Auto-generating cURL commands and client code snippets saves time and reduces errors.

### 8.2 cURL Generation from OpenAPI Spec

Build a module that generates cURL commands from the OpenAPI spec:

```elixir
defmodule Blackboex.SnippetGenerator.Curl do
  @moduledoc """
  Generates cURL commands from API endpoint definitions.
  """

  @spec generate(map()) :: String.t()
  def generate(%{method: method, url: url} = request) do
    parts = ["curl"]

    parts = parts ++ ["-X #{String.upcase(method)}"]
    parts = parts ++ [~s("#{url}")]

    parts =
      if request[:headers] do
        parts ++
          Enum.map(request.headers, fn {k, v} ->
            ~s(-H "#{k}: #{v}")
          end)
      else
        parts
      end

    parts =
      if request[:body] && method in ~w(POST PUT PATCH) do
        json = Jason.encode!(request.body, pretty: true)
        parts ++ [~s(-d '#{json}')]
      else
        parts
      end

    Enum.join(parts, " \\\n  ")
  end
end
```

**Example output:**

```bash
curl \
  -X POST \
  "https://blackboex.app/api/v1/todos" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk_test_abc123" \
  -d '{
  "title": "Buy groceries",
  "completed": false
}'
```

### 8.3 Multi-Language Code Snippet Generation

Generate client code in popular languages. Use EEx templates for each language:

```elixir
defmodule Blackboex.SnippetGenerator do
  @moduledoc """
  Generates code snippets in multiple languages from API definitions.
  """

  @languages ~w(curl python javascript elixir ruby go)a

  @spec generate(atom(), map()) :: String.t()
  def generate(:curl, request), do: Blackboex.SnippetGenerator.Curl.generate(request)
  def generate(:python, request), do: render_template("python.eex", request)
  def generate(:javascript, request), do: render_template("javascript.eex", request)
  def generate(:elixir, request), do: render_template("elixir.eex", request)
  def generate(:ruby, request), do: render_template("ruby.eex", request)
  def generate(:go, request), do: render_template("go.eex", request)

  @spec supported_languages() :: [atom()]
  def supported_languages, do: @languages

  defp render_template(template, request) do
    path = Path.join(:code.priv_dir(:blackboex_web), "templates/snippets/#{template}")
    EEx.eval_file(path, assigns: request)
  end
end
```

**Python template (`python.eex`):**

```python
import requests

url = "<%= @url %>"
<%= if @headers do %>
headers = {
<%= for {k, v} <- @headers do %>    "<%= k %>": "<%= v %>",
<% end %>}
<% end %>
<%= if @body do %>
payload = <%= Jason.encode!(@body, pretty: true) %>
<% end %>

response = requests.<%= String.downcase(@method) %>(
    url<%= if @headers do %>,
    headers=headers<% end %><%= if @body do %>,
    json=payload<% end %>
)

print(f"Status: {response.status_code}")
print(f"Body: {response.json()}")
```

**JavaScript template (`javascript.eex`):**

```javascript
const response = await fetch("<%= @url %>", {
  method: "<%= String.upcase(@method) %>",<%= if @headers do %>
  headers: {
<%= for {k, v} <- @headers do %>    "<%= k %>": "<%= v %>",
<% end %>  },<% end %><%= if @body do %>
  body: JSON.stringify(<%= Jason.encode!(@body, pretty: true) %>),<% end %>
});

const data = await response.json();
console.log(`Status: ${response.status}`);
console.log("Body:", data);
```

**Elixir template (`elixir.eex`):**

```elixir
{:ok, response} =
  Req.request(
    method: :<%= String.downcase(@method) %>,
    url: "<%= @url %>"<%= if @headers do %>,
    headers: [
<%= for {k, v} <- @headers do %>      {"<%= k %>", "<%= v %>"},
<% end %>    ]<% end %><%= if @body do %>,
    json: <%= inspect(@body, pretty: true) %><% end %>
  )

IO.puts("Status: #{response.status}")
IO.inspect(response.body, label: "Body")
```

### 8.4 OpenAPI-Based Code Generation Tools

For full client SDK generation, leverage existing tools:

- **[OpenAPI Generator](https://github.com/OpenAPITools/openapi-generator)**: Generates client SDKs in 50+ languages from OpenAPI specs. Has an [Elixir generator](https://openapi-generator.tech/docs/generators/elixir/).
- **[aj-foster/open-api-generator](https://github.com/aj-foster/open-api-generator)**: Elixir-specific code generator from OpenAPI descriptions.
- **[curlgenerator](https://github.com/christianhelle/curlgenerator)**: Dedicated tool for generating cURL from OpenAPI v2/v3 specs.

### 8.5 UX: Copy-to-Clipboard Code Snippets

In the API playground, add a "Code" panel with language tabs:

```text
+------------------------------------------+
| Code Snippets                            |
+------------------------------------------+
| [cURL] [Python] [JavaScript] [Elixir]   |
| [Ruby] [Go]                             |
+------------------------------------------+
| curl \                                   |
|   -X POST \                              |
|   "https://blackboex.app/api/v1/todos" \ |
|   -H "Content-Type: application/json" \  |
|   -d '{"title": "Test"}'                |
|                                          |
|                        [Copy to Clipboard]|
+------------------------------------------+
```

The snippet updates in real-time as the user modifies the request in the playground (method, path, headers, body).

---

## 9. Architecture Recommendation for BlackBoex

### 9.1 Phased Implementation

#### Phase 1: MVP (Weeks 1-3)

Focus on the core testing loop:

1. **LiveView API Playground** -- Custom request builder with method, path, headers, body, and response viewer. This is the centerpiece feature users interact with daily.
2. **Request/Response Logging** -- Telemetry-based recording with basic history view. Essential for debugging LLM-generated code.
3. **cURL Generation** -- Simple snippet generation from the current request. Low effort, high value.
4. **Basic Mock Data** -- Schema-driven fake data generation with Faker. Pre-fills request bodies.

#### Phase 2: Validation (Weeks 4-6)

Add confidence-building features:

5. **Auto-Generated Tests** -- LLM generates ExUnit tests alongside the API code. Show pass/fail results in the UI.
6. **Contract Validation** -- Runtime response validation against the OpenAPI spec using `open_api_spex`.
7. **Swagger UI** -- Serve `OpenApiSpex.Plug.SwaggerUI` as an alternative testing interface at `/api/:id/docs`.

#### Phase 3: Advanced (Weeks 7-10)

Features for serious users:

8. **Multi-Language Snippets** -- Python, JavaScript, Ruby, Go code generation from EEx templates.
9. **Property-Based Tests** -- StreamData generators auto-created from schemas.
10. **Basic Load Testing** -- Simple concurrent request runner with latency/throughput dashboard.
11. **Test Environments** -- PostgreSQL schema isolation per API with seed data.

#### Phase 4: Platform (Weeks 11+)

12. **Full SDK Generation** -- OpenAPI Generator integration for full client libraries.
13. **Advanced Load Testing** -- k6 integration or Chaperon scenarios with distributed testing.
14. **Contract Health Dashboard** -- Historical compliance tracking and alerting.
15. **Collaborative Testing** -- Share test collections between team members.

### 9.2 Key Dependencies

```elixir
# mix.exs for the umbrella
# In apps/blackboex/mix.exs
defp deps do
  [
    {:open_api_spex, "~> 3.22"},      # OpenAPI spec + validation
    {:ex_json_schema, "~> 0.10"},     # JSON Schema validation
    {:faker, "~> 0.18", only: [:dev, :test]},  # Mock data
    {:stream_data, "~> 1.3", only: [:test]},   # Property testing
    {:dune, "~> 0.3"},               # Code sandbox
    {:req, "~> 0.5"},                # HTTP client for testing
    {:benchee, "~> 1.3", only: :dev},  # Micro-benchmarks
  ]
end
```

### 9.3 Module Organization

```text
apps/blackboex/lib/blackboex/
  api_spec/
    builder.ex              # Builds OpenAPI specs from API definitions
    cache.ex                # ETS cache for resolved specs
  test_generator/
    test_generator.ex       # LLM-based test generation + validation loop
    stream_data_builder.ex  # Generates StreamData generators from schemas
  mock_data/
    generator.ex            # Schema-driven fake data with Faker
  request_log/
    request_log.ex          # Context for CRUD on request entries
    entry.ex                # Ecto schema
  contract/
    validator.ex            # Runtime contract validation
    violations.ex           # Violation tracking
  load_test/
    runner.ex               # Concurrent request runner
    result.ex               # Result aggregation + stats
  sandbox/
    sandbox.ex              # Unified sandbox (Dune + DB isolation)
    tenant_sandbox.ex       # PostgreSQL schema management
  snippet_generator/
    snippet_generator.ex    # Multi-language dispatcher
    curl.ex                 # cURL generation
    templates/              # EEx templates per language

apps/blackboex_web/lib/blackboex_web/
  live/
    api_playground_live.ex  # Main testing UI
    api_playground_live.html.heex
    load_test_live.ex       # Load test runner + dashboard
    test_results_live.ex    # Auto-generated test results viewer
  plugs/
    request_recorder.ex     # Captures raw request bodies
    contract_validator.ex   # Runtime response validation
  components/
    code_editor.ex          # JSON/code editor component
    code_viewer.ex          # Syntax-highlighted response viewer
    key_value_editor.ex     # Headers/params editor
    snippet_tabs.ex         # Language-tabbed code snippets
```

### 9.4 Data Flow

```text
User describes API
       |
       v
LLM generates: [Elixir code] + [OpenAPI spec] + [ExUnit tests]
       |
       v
BlackBoex compiles + validates in Dune sandbox
       |
       v
API deployed to isolated PostgreSQL schema
       |
       v
User opens API Playground (LiveView)
  |-- Sends test requests -> Recorded in request_log
  |-- Views auto-generated tests -> Run in Ecto Sandbox
  |-- Checks contract compliance -> OpenApiSpex validation
  |-- Generates code snippets -> EEx templates
  |-- Runs load test -> Supervised concurrent workers
       |
       v
Results displayed in real-time via PubSub
```

### 9.5 Security Considerations

1. **Never execute LLM-generated code directly** -- Always run through Dune or equivalent sandbox.
2. **Database isolation is mandatory** -- One user's test data must never leak to another.
3. **Rate limit everything** -- API requests, test runs, load tests, LLM calls.
4. **Redact secrets in logs** -- Authorization headers, API keys, tokens.
5. **Timeout all operations** -- LLM code execution (5s), load tests (5min max), test suites (60s).
6. **Validate LLM output before compilation** -- Check for dangerous patterns (System.cmd, File, Port, etc.) even before sandboxing.

---

## Sources

- [open_api_spex - GitHub](https://github.com/open-api-spex/open_api_spex)
- [OpenApiSpex.Plug.SwaggerUI - HexDocs](https://hexdocs.pm/open_api_spex/OpenApiSpex.Plug.SwaggerUI.html)
- [open_api_spex - HexDocs v3.22.2](https://hexdocs.pm/open_api_spex/)
- [ex_json_schema - GitHub](https://github.com/jonasschmidt/ex_json_schema)
- [StreamData - GitHub](https://github.com/whatyouhide/stream_data)
- [StreamData - HexDocs v1.3.0](https://hexdocs.pm/stream_data/StreamData.html)
- [ExUnitProperties - HexDocs](https://hexdocs.pm/stream_data/ExUnitProperties.html)
- [Chaperon - GitHub](https://github.com/polleverywhere/chaperon)
- [Chaperon - Hex.pm](https://hex.pm/packages/chaperon)
- [elixir-k6 - GitHub](https://github.com/besughi/elixir-k6)
- [Benchee - GitHub](https://github.com/bencheeorg/benchee)
- [Dune - Elixir Sandbox - GitHub](https://github.com/functional-rewire/dune)
- [Exbox - GitHub](https://github.com/christhekeele/exbox)
- [Phoenix Telemetry - HexDocs](https://hexdocs.pm/phoenix/telemetry.html)
- [Plug.Telemetry - HexDocs](https://hexdocs.pm/plug/Plug.Telemetry.html)
- [OpenAPI Generator - GitHub](https://github.com/OpenAPITools/openapi-generator)
- [OpenAPI Generator Elixir Docs](https://openapi-generator.tech/docs/generators/elixir/)
- [aj-foster/open-api-generator - GitHub](https://github.com/aj-foster/open-api-generator)
- [curlgenerator - GitHub](https://github.com/christianhelle/curlgenerator)
- [Meta TestGen-LLM - arXiv](https://arxiv.org/abs/2402.09171)
- [Meta ACH - LLM Bug Catchers](https://engineering.fb.com/2025/02/05/security/revolutionizing-software-testing-llm-powered-bug-catchers-meta-ach/)
- [TestPilot - GitHub](https://github.com/githubnext/testpilot)
- [Qodo TestGen-LLM Implementation](https://www.qodo.ai/blog/we-created-the-first-open-source-implementation-of-metas-testgen-llm/)
- [Contract Testing with OpenAPI - Speakeasy](https://www.speakeasy.com/blog/contract-testing-with-openapi)
- [Schema-based Contract Testing - PactFlow](https://pactflow.io/blog/contract-testing-using-json-schemas-and-open-api-part-2/)
- [k6 Load Testing - Elixir Merge](https://elixirmerge.com/p/integration-of-k6-load-testing-with-elixirs-liveview)
- [k6 Load Testing - Grafana](https://k6.io/)
- [Phoenix LiveView - HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
- [Elixir Sandbox Discussion - Google Groups](https://groups.google.com/g/elixir-lang-talk/c/-Cmh_O2zS5E)
- [Elixir Sandbox Discussion - Forum](https://elixirforum.com/t/how-to-create-a-sandbox-to-run-untrusted-code-modules/4142)
