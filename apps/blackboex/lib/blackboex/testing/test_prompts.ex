defmodule Blackboex.Testing.TestPrompts do
  @moduledoc """
  Prompt templates for LLM-based test generation.
  Generates unit tests that call handler functions via the `Handler` module.
  The TestRunner automatically compiles the handler code into a `Handler` module
  before running tests, so tests just call `Handler.handle(params)` directly.
  """

  alias Blackboex.Apis.Api

  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are an expert Elixir test engineer. You generate ExUnit test modules \
    that validate API handler functions by calling them through the `Handler` module.

    ## Critical Architecture
    The handler functions are automatically available in a module called `Handler`. \
    You do NOT need to define or import them — just call `Handler.handle(params)`, \
    `Handler.handle_list(params)`, etc.

    DO NOT copy or duplicate the handler code into the test module. \
    The `Handler` module is compiled separately and available at test runtime.

    ## Rules

    1. Generate a COMPLETE ExUnit test module with `defmodule` and `use ExUnit.Case`.
    2. Call handler functions via `Handler.handle(params)` — NOT via HTTP, NOT by redefining them.
    3. DO NOT define `def handle`, `def handle_list`, etc. in the test module.
    4. Assert on the returned map structure and values.
    5. Do NOT use `Req`, `HTTPoison`, or any HTTP client.
    6. Do NOT use `File`, `System`, `Code`, `Process`, or any I/O modules.
    7. Include at MINIMUM 5 test cases:
       - Happy path (valid input → expected output)
       - Edge case (boundary values, empty input)
       - Invalid input (wrong types, missing fields)
       - At least 2 additional relevant scenarios
    8. Use `assert` and `refute` — not `IO.inspect` or `Logger`.
    9. Tests must be self-contained — no external dependencies.

    ## Test Code Quality Requirements
    - The test module MUST have a @moduledoc describing what it tests
    - Use descriptive test names that explain the scenario and expected outcome
    - Code MUST be compatible with `mix format`
    - Use descriptive variable names
    - Group related tests together using `describe` blocks

    ## Example
    ```elixir
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the calculator API handler."
      use ExUnit.Case

      describe "happy path" do
        test "adds two numbers correctly" do
          result = Handler.handle(%{"a" => 1, "b" => 2})
          assert result == %{result: 3}
        end
      end

      describe "error handling" do
        test "returns error for missing parameters" do
          result = Handler.handle(%{})
          assert %{error: _} = result
        end
      end
    end
    ```

    ## Output Format
    Return ONLY a single ```elixir code block containing the full test module.
    No explanations before or after.
    """
  end

  @spec build_generation_prompt(Api.t(), map()) :: String.t()
  def build_generation_prompt(%Api{} = api, _openapi_spec) do
    """
    Generate ExUnit unit tests for the following API handler.
    The handler functions are available via the `Handler` module — call them directly.

    ## API Details
    - Name: #{sanitize_field(api.name)}
    - Type: #{api.template_type}
    - Description: #{sanitize_field(api.description || "No description")}

    ## Handler Source Code (for reference only — DO NOT copy into tests)
    ```elixir
    #{sanitize_code_fence(api.source_code || "# No source code available")}
    ```

    ## Available Functions (call via Handler module)
    #{handler_functions_hint(api.template_type)}

    ## Instructions
    1. Call `Handler.handle(...)` (or other Handler functions) with different inputs.
    2. Assert on the returned maps — check keys, values, and types.
    3. Test both success and error scenarios.
    4. The module name MUST be `GeneratedAPITest`.
    5. DO NOT redefine handler functions in the test module.

    Generate the complete ExUnit test module now.
    """
  end

  @spec build_retry_prompt(String.t(), String.t()) :: String.t()
  def build_retry_prompt(previous_code, compile_error) do
    """
    The following ExUnit test code has compilation errors. \
    Fix the errors and return the corrected COMPLETE test module.

    ## Previous Code
    ```elixir
    #{previous_code}
    ```

    ## Compilation Error
    ```
    #{compile_error}
    ```

    Remember:
    - Call handler functions via `Handler.handle(...)` — do NOT redefine them
    - The `Handler` module is provided automatically at runtime
    - Do NOT use HTTP requests

    Return the corrected code in a single ```elixir code block.
    """
  end

  @spec parse_response(String.t()) :: {:ok, String.t()} | {:error, :no_code_found}
  def parse_response(response) do
    case Regex.run(~r/```(?:elixir)?\s*[\r\n](.*?)```/s, response) do
      [_, code] -> {:ok, String.trim(code)}
      _ -> {:error, :no_code_found}
    end
  end

  defp handler_functions_hint("crud") do
    """
    - `Handler.handle_list(params)` — list items
    - `Handler.handle_get(id, params)` — get item by ID
    - `Handler.handle_create(params)` — create item
    - `Handler.handle_update(id, params)` — update item
    - `Handler.handle_delete(id)` — delete item
    """
  end

  defp handler_functions_hint("webhook") do
    "- `Handler.handle_webhook(payload)` — process webhook payload"
  end

  defp handler_functions_hint(_) do
    "- `Handler.handle(params)` — main computation function"
  end

  defp sanitize_code_fence(text) do
    String.replace(text, "```", "` ` `")
  end

  defp sanitize_field(text) do
    text
    |> String.replace(~r/[```]/, "")
    |> String.slice(0, 10_000)
  end
end
