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
    - Cover the full spectrum: happy paths, edge cases, validation, error messages
    - Tests must exercise the FULL end-to-end flow: params → handler → response with ALL fields checked

    ## Architecture
    The handler functions are available in a module called `Handler`.
    DO NOT copy or redefine handler code — just call `Handler.handle(params)`, etc.
    The `Handler` module is compiled separately and available at test runtime.
    The Request/Response DTOs are also available as `Handler.Request` and `Handler.Response`.
    Nested schemas (e.g., Vehicle, Driver) are available as `Handler.Vehicle`, `Handler.Driver`, etc.

    ## Rules
    1. Generate a COMPLETE ExUnit test module with `defmodule GeneratedAPITest` and `use ExUnit.Case`.
    2. Call handler functions via `Handler.handle(params)` — NOT via HTTP.
    3. DO NOT define handler functions in the test module.
    4. Do NOT use `Req`, `HTTPoison`, `File`, `System`, `Code`, or `Process`.
    5. Use `assert` and `refute` only.

    ## Test Coverage Requirements (MANDATORY — ALL categories must be present)

    ### 1. Input Validation (via Changeset)
    - Test `Handler.Request.changeset/1` with COMPLETE valid params → `changeset.valid? == true`
    - Test with missing required fields → `changeset.valid? == false`
    - Test with wrong types (string where integer expected)
    - Test with boundary values (zero, negative, very large)
    - Verify error messages are descriptive

    ### 2. Nested Schema Validation (CRITICAL for APIs with embeds)
    If the Request schema uses `embeds_one` or `embeds_many` (nested objects like vehicle, driver,
    items, address, etc.), you MUST test:
    - Nested changeset directly: `Handler.Vehicle.changeset(%Handler.Vehicle{}, %{"year" => 2023, ...})`
    - Request changeset with COMPLETE nested data (all nested objects populated with valid values)
    - Request changeset with MISSING nested objects → changeset invalid
    - Request changeset with INVALID nested field values → changeset invalid
    - Each nested schema's individual validations (required fields, value ranges, formats)

    IMPORTANT: Nested schema changesets are called with ARITY 2 (struct + params) because
    Ecto's `cast_embed` passes the struct. Always test with:
    `Handler.Vehicle.changeset(%Handler.Vehicle{}, params)` — NOT `Handler.Vehicle.changeset(params)`.

    ### 3. Happy Path — End-to-End
    - Test `Handler.handle(params)` with COMPLETE, REALISTIC input including ALL nested objects
    - Assert EVERY key in the response map is present and has the correct type
    - Test with MULTIPLE different valid inputs to show behavior range
    - For APIs with nested input, ALWAYS build full params with nested maps:
      ```elixir
      params = %{
        "coverage" => "comprehensive",
        "vehicle" => %{"year" => 2023, "category" => "sedan", "value_brl" => 80000},
        "driver" => %{"age" => 30, "license_years" => 8, "claims_last_3y" => 0, "zip_prefix" => "01"}
      }
      result = Handler.handle(params)
      assert is_float(result.monthly_premium_brl)
      assert result.monthly_premium_brl > 0
      assert is_map(result.breakdown)
      assert is_binary(result.risk_score)
      ```
    - **NEVER use `==` to compare computed float values** — floating point arithmetic is imprecise.
      Use `abs(expected - actual) < 0.1` for monetary values or `assert is_float(result.value)`.
      Only use `==` for exact integers or known string/atom values.
    - When asserting a value is positive, use `assert result > 0` (not `> 0.0`) since
      the handler may return integer 0 or float 0.0 depending on the computation.

    ### 4. Response Structure Validation
    - Assert ALL top-level keys are present in the success response
    - Assert nested response maps (like `breakdown`, `details`) have all expected keys
    - Assert value types: `is_float`, `is_integer`, `is_binary`, `is_map`, `is_boolean`, `is_list`
    - Assert value ranges where applicable: prices > 0, percentages between 0-100, etc.
    - Assert enum/string values are within expected options

    ### 5. Error Handling
    - Test with empty params `%{}`
    - Test with invalid/out-of-range values
    - Test with partial params (some fields missing)
    - Verify error responses have `%{error: message}` structure
    - Verify error messages are human-readable

    ### 6. Edge Cases & Corner Cases
    - Boundary values (minimum valid, maximum valid, just below minimum, just above maximum)
    - Zero values where applicable (0 claims, 0 years, price of 0)
    - Very large values (999999, very old dates, very high prices)
    - Different valid combinations (each enum value, each category, each coverage type)
    - Type coercion scenarios (string "5" vs integer 5)
    - Nil values, missing keys
    - Special characters in string inputs

    ### 7. Business Logic Variations
    - Test each branch of business logic (every category, every coverage type, every age range)
    - Verify that different inputs produce DIFFERENT outputs (not all the same result)
    - Test that factors/multipliers affect the result in the expected direction
      (e.g., more claims → higher premium, more experience → lower premium)

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
      Tests for the Insurance Quote API handler.

      Validates the full contract: nested schema validation, premium calculation
      for different vehicle/driver profiles, coverage types, and error handling.
      \"\"\"
      use ExUnit.Case

      # Shared valid params — full nested structure for reuse across tests
      @valid_params %{
        "coverage" => "comprehensive",
        "vehicle" => %{"year" => 2023, "category" => "sedan", "value_brl" => 80000.0},
        "driver" => %{"age" => 35, "license_years" => 10, "claims_last_3y" => 0, "zip_prefix" => "30"}
      }

      # --- Nested Schema Validation ---
      # Nested schemas are the building blocks. Each must validate independently.

      describe "Vehicle changeset" do
        test "accepts valid vehicle data" do
          changeset = Handler.Vehicle.changeset(%Handler.Vehicle{}, %{
            "year" => 2023, "category" => "sedan", "value_brl" => 80000
          })
          assert changeset.valid?
        end

        test "rejects missing required fields" do
          changeset = Handler.Vehicle.changeset(%Handler.Vehicle{}, %{})
          refute changeset.valid?
        end
      end

      # --- Request Changeset with Full Nested Data ---
      # The Request changeset must validate the entire nested structure.

      describe "Request changeset validation" do
        test "accepts complete valid params with nested objects" do
          changeset = Handler.Request.changeset(@valid_params)
          assert changeset.valid?
        end

        test "rejects missing nested objects" do
          changeset = Handler.Request.changeset(%{"coverage" => "comprehensive"})
          refute changeset.valid?
        end
      end

      # --- Happy Path: Full End-to-End ---
      # Prove that valid input produces a complete, correct response.

      describe "successful quote calculation" do
        test "returns complete response with all fields" do
          result = Handler.handle(@valid_params)
          # Verify every key exists and has correct type
          assert is_float(result.monthly_premium_brl)
          assert result.monthly_premium_brl > 0
          assert is_float(result.annual_premium_brl)
          assert is_map(result.breakdown)
          assert is_binary(result.risk_score)
          assert is_float(result.deductible_brl)
          assert is_map(result.coverage_details)
        end

        test "more claims produce higher premium" do
          low = Handler.handle(@valid_params)
          high_claims = put_in(@valid_params, ["driver", "claims_last_3y"], 3)
          high = Handler.handle(high_claims)
          assert high.monthly_premium_brl > low.monthly_premium_brl
        end
      end

      # --- Error Handling ---

      describe "error handling" do
        test "returns error for empty params" do
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

  @spec build_generation_prompt(Api.t(), map(), String.t() | nil) :: String.t()
  def build_generation_prompt(%Api{} = api, _openapi_spec, source_code \\ nil) do
    """
    Generate ExUnit unit tests for the following API handler.
    The handler functions are available via the `Handler` module — call them directly.

    ## API Details
    - Name: #{sanitize_field(api.name)}
    - Type: #{api.template_type}
    - Description: #{sanitize_field(api.description || "No description")}

    ## Handler Source Code (for reference only — DO NOT copy into tests)
    ```elixir
    #{sanitize_code_fence(source_code || "# No source code available")}
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
