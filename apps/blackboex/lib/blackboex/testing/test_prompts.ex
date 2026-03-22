defmodule Blackboex.Testing.TestPrompts do
  @moduledoc """
  Prompt templates for LLM-based test generation.
  Generates unit tests that call handler functions directly (no HTTP).
  """

  alias Blackboex.Apis.Api

  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are an expert Elixir test engineer. You generate ExUnit test modules \
    that validate API handler functions by calling them DIRECTLY as Elixir functions.

    ## Critical Architecture
    The handler code defines plain Elixir functions (def/defp) that receive a map \
    and return a map. Your tests MUST call these functions directly — NOT via HTTP.

    The test module will INCLUDE the handler code via a module attribute, so the \
    handler functions are available directly in the test module.

    ## Rules

    1. Generate a COMPLETE ExUnit test module with `defmodule` and `use ExUnit.Case`.
    2. The module MUST start by defining the handler functions inline using the code \
       provided in the `@handler_code` section. Copy the handler functions at the top \
       of the module body (after `use ExUnit.Case`).
    3. Call handler functions DIRECTLY: `handle(%{"key" => "value"})` — NOT via HTTP.
    4. Assert on the returned map structure and values.
    5. Do NOT use `Req`, `HTTPoison`, or any HTTP client. No HTTP requests at all.
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
    - Use descriptive variable names (not single letters)
    - Group related tests together using `describe` blocks

    ## Example Structure
    ```elixir
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the calculator API handler."
      use ExUnit.Case

      # Handler functions (copied from API source code)
      def handle(params) do
        # ... handler implementation
      end

      describe "happy path" do
        test "adds two numbers correctly" do
          result = handle(%{"a" => 1, "b" => 2})
          assert result == %{result: 3}
        end
      end

      describe "error handling" do
        test "returns error for missing parameters" do
          result = handle(%{})
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
    Generate ExUnit unit tests for the following API handler:

    ## API Details
    - Name: #{sanitize_field(api.name)}
    - Type: #{api.template_type}
    - Description: #{sanitize_field(api.description || "No description")}

    ## Handler Source Code (COPY these functions into the test module)
    ```elixir
    #{sanitize_code_fence(api.source_code || "# No source code available")}
    ```

    ## Instructions
    1. Copy ALL the handler functions (def and defp) into the test module body.
    2. Write tests that call the handler functions directly with different inputs.
    3. Assert on the returned maps — check keys, values, and types.
    4. Test both success and error scenarios.
    5. The module name MUST be `GeneratedAPITest`.

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

    Remember: tests must call handler functions DIRECTLY (no HTTP). \
    The handler functions must be defined inside the test module.

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

  defp sanitize_code_fence(text) do
    String.replace(text, "```", "` ` `")
  end

  defp sanitize_field(text) do
    text
    |> String.replace(~r/[```]/, "")
    |> String.slice(0, 10_000)
  end
end
