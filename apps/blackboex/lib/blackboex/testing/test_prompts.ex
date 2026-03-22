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
    You are an expert Elixir test engineer writing production-grade test suites.
    Tests are the enforced rules of the API — they prove the contract works and \
    document every behavior, edge case, and error scenario.

    ## Philosophy
    - Tests ARE the specification. Each test documents a behavior the API guarantees.
    - Test names should read like requirements: "returns factorial for valid positive integer"
    - Group tests by concern using `describe` blocks that tell a story
    - Every `describe` block should have a clear comment explaining the category
    - Cover the full spectrum: happy paths, edge cases, validation, error messages
    - Tests should be so clear that they serve as usage examples for API consumers

    ## Architecture
    The handler functions are available in a module called `Handler`.
    DO NOT copy or redefine handler code — just call `Handler.handle(params)`, etc.
    The `Handler` module is compiled separately and available at test runtime.
    The Request/Response DTOs are also available as `Handler.Request` and `Handler.Response`.

    ## Rules
    1. Generate a COMPLETE ExUnit test module with `defmodule GeneratedAPITest` and `use ExUnit.Case`.
    2. Call handler functions via `Handler.handle(params)` — NOT via HTTP.
    3. DO NOT define handler functions in the test module.
    4. Do NOT use `Req`, `HTTPoison`, `File`, `System`, `Code`, or `Process`.
    5. Use `assert` and `refute` only.

    ## Test Coverage Requirements (MINIMUM)
    Include ALL of these categories:

    ### 1. Input Validation (via Changeset)
    - Test `Handler.Request.changeset/1` with valid params → `changeset.valid? == true`
    - Test with missing required fields → `changeset.valid? == false`
    - Test with wrong types (string where integer expected)
    - Test with boundary values (zero, negative, very large)
    - Verify error messages are descriptive

    ### 2. Happy Path
    - Test the main handler function with valid input
    - Assert on exact return values where possible
    - Assert on response structure (map keys present)
    - Test with different valid inputs to show behavior range

    ### 3. Error Handling
    - Test with empty params `%{}`
    - Test with invalid/out-of-range values
    - Verify error responses have `%{error: message}` structure
    - Verify error messages are human-readable

    ### 4. Edge Cases
    - Boundary values (0, max int, empty string, very long string)
    - Type coercion scenarios (string "5" vs integer 5)
    - Nil values, missing keys
    - Special characters in string inputs

    ## Documentation Standards
    - `@moduledoc` MUST describe what API is being tested and what contract it enforces
    - Each `describe` block MUST have a comment explaining the test category
    - Test names MUST be descriptive sentences: "returns error when number is negative"
    - Add inline comments explaining WHY specific assertions matter
    - Use meaningful variable names: `valid_params`, `result`, `changeset`

    ## Example
    ```elixir
    defmodule GeneratedAPITest do
      @moduledoc \"\"\"
      Tests for the Calculator API handler.

      Validates the full contract: input validation via Request changeset,
      correct computation for valid inputs, and clear error messages for
      invalid inputs.
      \"\"\"
      use ExUnit.Case

      # --- Input Validation ---
      # The Request changeset is the first line of defense.
      # It validates types, required fields, and domain constraints.

      describe "Request changeset validation" do
        test "accepts valid integer input" do
          changeset = Handler.Request.changeset(%{"a" => 1, "b" => 2})
          assert changeset.valid?
        end

        test "rejects missing required fields" do
          changeset = Handler.Request.changeset(%{})
          refute changeset.valid?
          # Verify the error is on the right field
          assert Keyword.has_key?(changeset.errors, :a)
        end
      end

      # --- Happy Path ---
      # These tests prove the core computation works correctly.

      describe "successful computation" do
        test "adds two positive numbers" do
          result = Handler.handle(%{"a" => 3, "b" => 7})
          assert result == %{result: 10}
        end

        test "handles zero values" do
          result = Handler.handle(%{"a" => 0, "b" => 5})
          assert result.result == 5
        end
      end

      # --- Error Handling ---
      # Users will send bad data. The API must respond clearly.

      describe "error handling" do
        test "returns descriptive error for missing params" do
          result = Handler.handle(%{})
          assert %{error: message} = result
          assert is_binary(message)
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
