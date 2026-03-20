defmodule Blackboex.Testing.TestPrompts do
  @moduledoc """
  Prompt templates for LLM-based test generation.
  """

  alias Blackboex.Apis.Api

  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are an expert Elixir test engineer. You generate ExUnit test modules \
    that validate REST API endpoints via HTTP requests.

    ## Rules

    1. Generate a COMPLETE ExUnit test module with `defmodule` and `use ExUnit.Case`.
    2. Use `Req.post/2`, `Req.get/2`, etc. for HTTP requests.
    3. Assert on: status codes, response body structure, field values.
    4. Include at MINIMUM 5 test cases:
       - Happy path (valid input → expected output)
       - Edge case (boundary values, empty input)
       - Invalid input (wrong types, missing fields)
       - At least 2 additional relevant scenarios
    5. Use `assert` and `refute` — not `IO.inspect` or `Logger`.
    6. Tests must be self-contained — no external dependencies beyond `Req` and `Jason`.
    7. Do NOT use `File`, `System`, `Code`, `Process`, or any I/O modules.

    ## Output Format
    Return ONLY a single ```elixir code block containing the full test module.
    No explanations before or after.
    """
  end

  @spec build_generation_prompt(Api.t(), map()) :: String.t()
  def build_generation_prompt(%Api{} = api, openapi_spec) do
    spec_json = Jason.encode!(openapi_spec, pretty: true)

    """
    Generate ExUnit tests for the following API:

    ## API Details
    - Name: #{sanitize_field(api.name)}
    - Type: #{api.template_type}
    - Method: #{api.method}
    - Requires Auth: #{api.requires_auth}
    - Description: #{sanitize_field(api.description || "No description")}

    ## API Source Code
    ```elixir
    #{sanitize_code_fence(api.source_code || "# No source code available")}
    ```

    ## OpenAPI Spec
    ```json
    #{spec_json}
    ```

    ## API URL
    Use `@api_url` module attribute set to a placeholder URL.

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

  # Escape triple backticks in user content to prevent prompt structure breakout
  defp sanitize_code_fence(text) do
    String.replace(text, "```", "` ` `")
  end

  # Strip control characters from user-provided text fields
  defp sanitize_field(text) do
    text
    |> String.replace(~r/[```]/, "")
    |> String.slice(0, 10_000)
  end
end
