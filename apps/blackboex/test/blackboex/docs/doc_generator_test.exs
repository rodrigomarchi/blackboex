defmodule Blackboex.Docs.DocGeneratorTest do
  use ExUnit.Case, async: false

  @moduletag :unit

  import Mox

  alias Blackboex.Apis.Api
  alias Blackboex.Docs.DocGenerator

  setup :verify_on_exit!

  @test_api %Api{
    id: Ecto.UUID.generate(),
    name: "Calculator",
    slug: "calculator",
    description: "A calculator API",
    template_type: "computation",
    method: "POST",
    status: "published",
    visibility: "public",
    requires_auth: true,
    param_schema: %{"number" => "integer"},
    example_request: %{"number" => 42},
    example_response: %{"result" => 84},
    source_code: "def handle(%{\"number\" => n}), do: %{result: n * 2}"
  }

  @valid_markdown """
  # Calculator API

  A calculator API that doubles numbers.

  ## Authentication

  This API requires an API key. Include it in the `X-Api-Key` header.

  ## Endpoints

  ### POST /

  Doubles the given number.

  **Request Body:**
  ```json
  {"number": 42}
  ```

  **Response:**
  ```json
  {"result": 84}
  ```

  ## Error Codes

  - `400` - Bad request
  - `500` - Internal server error

  ## Code Examples

  ### cURL
  ```bash
  curl -X POST https://api.example.com/api/org/calculator -H "X-Api-Key: your_key" -d '{"number": 42}'
  ```
  """

  describe "generate/2" do
    test "returns markdown documentation" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @valid_markdown, usage: %{}}}
      end)

      assert {:ok, markdown} = DocGenerator.generate(@test_api)
      assert is_binary(markdown)
      assert String.contains?(markdown, "Calculator")
    end

    test "returns error when LLM fails" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:error, :api_error}
      end)

      assert {:error, :generation_failed} = DocGenerator.generate(@test_api)
    end
  end
end
