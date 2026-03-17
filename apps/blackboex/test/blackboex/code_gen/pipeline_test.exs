defmodule Blackboex.CodeGen.PipelineTest do
  use ExUnit.Case, async: true

  import Mox

  @moduletag :unit

  alias Blackboex.CodeGen.{GenerationResult, Pipeline}

  setup :verify_on_exit!

  @llm_response """
  Here is the code:

  ```elixir
  def call(conn, %{"celsius" => celsius}) do
    fahrenheit = celsius * 9 / 5 + 32
    json(conn, %{fahrenheit: fahrenheit})
  end
  ```
  """

  describe "generate/2" do
    test "returns GenerationResult on success" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @llm_response, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      assert {:ok, %GenerationResult{} = result} =
               Pipeline.generate("Convert Celsius to Fahrenheit", user_id: "user-1")

      assert result.code =~ "fahrenheit"
      assert result.template == :computation
      assert result.description == "Convert Celsius to Fahrenheit"
      assert is_binary(result.provider)
      assert result.tokens_used > 0
    end

    @tag :capture_log
    test "returns error when LLM fails" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:error, :api_error}
      end)

      assert {:error, :api_error} =
               Pipeline.generate("Some description", user_id: "user-1")
    end

    test "returns error when response contains no code" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{content: "I cannot generate that code.", usage: %{input_tokens: 10, output_tokens: 20}}}
      end)

      assert {:error, :no_code_in_response} =
               Pipeline.generate("Some description", user_id: "user-1")
    end
  end

  describe "classify_type/1" do
    test "classifies CRUD keywords" do
      assert Pipeline.classify_type("CRUD API for users") == :crud
      assert Pipeline.classify_type("store items in database") == :crud
      assert Pipeline.classify_type("listar todos os produtos") == :crud
      assert Pipeline.classify_type("armazenar dados") == :crud
      assert Pipeline.classify_type("persist user data") == :crud
    end

    test "does not falsely classify generic words as CRUD" do
      assert Pipeline.classify_type("list of prime numbers") == :computation
      assert Pipeline.classify_type("create a fibonacci sequence") == :computation
    end

    test "classifies webhook keywords" do
      assert Pipeline.classify_type("receive Stripe webhook") == :webhook
      assert Pipeline.classify_type("webhook callback handler") == :webhook
      assert Pipeline.classify_type("receber notificação") == :webhook
    end

    test "defaults to computation" do
      assert Pipeline.classify_type("Convert Celsius to Fahrenheit") == :computation
      assert Pipeline.classify_type("Calculate factorial") == :computation
    end
  end

  describe "extract_code/1" do
    test "extracts code from markdown code block" do
      response = """
      Here is the code:

      ```elixir
      def call(conn, params) do
        json(conn, %{ok: true})
      end
      ```
      """

      assert {:ok, code} = Pipeline.extract_code(response)
      assert code =~ "def call(conn, params)"
    end

    test "returns error when no code block found" do
      assert {:error, :no_code_in_response} = Pipeline.extract_code("No code here")
    end

    test "handles code block without elixir tag" do
      response = """
      ```
      def call(conn, params), do: json(conn, %{})
      ```
      """

      assert {:ok, code} = Pipeline.extract_code(response)
      assert code =~ "def call"
    end
  end
end
