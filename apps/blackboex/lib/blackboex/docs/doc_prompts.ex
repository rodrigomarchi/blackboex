defmodule Blackboex.Docs.DocPrompts do
  @moduledoc """
  Prompt templates for LLM-based API documentation generation.
  """

  alias Blackboex.Apis.Api

  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are a technical writer specializing in API documentation. \
    Generate clear, comprehensive Markdown documentation for REST APIs.

    ## Requirements

    1. Write in clear, concise English.
    2. Include all sections: description, authentication, endpoints, \
    request/response examples, error codes, rate limiting, and code examples.
    3. Use proper Markdown formatting with headers, code blocks, and tables.
    4. Code examples should include: cURL, Python (requests), JavaScript (fetch), and Elixir (Req).
    5. Return ONLY the Markdown content — no preamble or meta-commentary.
    """
  end

  @spec build_doc_prompt(Api.t(), map(), String.t() | nil) :: String.t()
  def build_doc_prompt(%Api{} = api, openapi_spec, source_code \\ nil) do
    spec_json = Jason.encode!(openapi_spec, pretty: true)

    """
    Generate comprehensive API documentation for the following API:

    ## API Details
    - Name: #{sanitize_field(api.name)}
    - Description: #{sanitize_field(api.description || "No description provided")}
    - Type: #{api.template_type}
    - Method: #{api.method}
    - Requires Authentication: #{api.requires_auth}

    ## Source Code
    ```elixir
    #{sanitize_code_fence(source_code || "# No source code available")}
    ```

    ## OpenAPI Specification
    ```json
    #{spec_json}
    ```

    Generate the complete Markdown documentation now.
    """
  end

  # Escape triple backticks in user content to prevent prompt structure breakout
  defp sanitize_code_fence(text) do
    String.replace(text, "```", "` ` `")
  end

  # Strip backticks from user-provided text fields and cap length
  defp sanitize_field(text) do
    text
    |> String.replace(~r/[```]/, "")
    |> String.slice(0, 10_000)
  end
end
