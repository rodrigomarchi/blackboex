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
    example_response: %{"result" => 84}
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
    test "returns markdown documentation with doc and usage keys" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @valid_markdown, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      assert {:ok, %{doc: markdown, usage: usage}} = DocGenerator.generate(@test_api)
      assert is_binary(markdown)
      assert String.length(markdown) > 0
      assert String.contains?(markdown, "Calculator")
      assert Map.has_key?(usage, :input_tokens)
      assert Map.has_key?(usage, :output_tokens)
    end

    test "generated doc is a non-empty string" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @valid_markdown, usage: %{}}}
      end)

      assert {:ok, %{doc: markdown}} = DocGenerator.generate(@test_api)
      assert is_binary(markdown)
      assert String.length(markdown) > 0
    end

    test "usage map contains input_tokens and output_tokens keys" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Doc", usage: %{input_tokens: 50, output_tokens: 75}}}
      end)

      assert {:ok, %{usage: usage}} = DocGenerator.generate(@test_api)
      assert Map.has_key?(usage, :input_tokens)
      assert Map.has_key?(usage, :output_tokens)
    end

    test "returns error when LLM fails" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:error, :api_error}
      end)

      assert {:error, :generation_failed} = DocGenerator.generate(@test_api)
    end

    test "delivers tokens to callback when token_callback option is provided" do
      tokens = ["# Calculator", "\n\n", "A calculator API."]
      stream = Stream.map(tokens, &{:token, &1})

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts ->
        {:ok, stream}
      end)

      test_pid = self()

      result =
        DocGenerator.generate(@test_api,
          client: Blackboex.LLM.ClientMock,
          token_callback: fn token -> send(test_pid, {:token, token}) end
        )

      assert {:ok, %{doc: doc}} = result
      assert is_binary(doc)
      assert String.length(doc) > 0

      for token <- tokens do
        assert_received {:token, ^token}
      end
    end

    test "streaming returns error when LLM stream_text fails" do
      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts ->
        {:error, :stream_error}
      end)

      assert {:error, :generation_failed} =
               DocGenerator.generate(@test_api,
                 client: Blackboex.LLM.ClientMock,
                 token_callback: fn _token -> :ok end
               )
    end

    test "handles API with nil source_code gracefully" do
      api_nil_source = %Api{
        id: Ecto.UUID.generate(),
        name: "Test API",
        template_type: "computation"
      }

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Test API\n\nNo source.", usage: %{}}}
      end)

      result = DocGenerator.generate(api_nil_source, client: Blackboex.LLM.ClientMock)
      assert {:ok, %{doc: doc}} = result
      assert is_binary(doc)
    end

    test "handles API with empty string source_code gracefully" do
      api_empty_source = %Api{
        id: Ecto.UUID.generate(),
        name: "Test API",
        template_type: "computation"
      }

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: "# Test API\n\nEmpty source.", usage: %{}}}
      end)

      result = DocGenerator.generate(api_empty_source, client: Blackboex.LLM.ClientMock)
      assert {:ok, %{doc: doc}} = result
      assert is_binary(doc)
    end
  end
end
