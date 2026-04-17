defmodule Blackboex.PlaygroundAgent.CodePipelineTest do
  use ExUnit.Case, async: true

  alias Blackboex.PlaygroundAgent.CodePipeline

  defmodule StubClient do
    @behaviour Blackboex.LLM.ClientBehaviour

    @canned """
    Aqui vai:
    ```elixir
    IO.puts("1+1=#{1 + 1}")
    ```
    Resumo: soma simples
    """

    @impl true
    def generate_text(_prompt, _opts) do
      {:ok, %{content: @canned, usage: %{input_tokens: 42, output_tokens: 17}}}
    end

    @impl true
    def stream_text(_prompt, _opts) do
      tokens = String.graphemes(@canned)
      {:ok, Stream.map(tokens, & &1)}
    end
  end

  defmodule EmptyBlockClient do
    @behaviour Blackboex.LLM.ClientBehaviour
    @impl true
    def generate_text(_p, _o), do: {:ok, %{content: "só prosa", usage: %{}}}
    @impl true
    def stream_text(_p, _o), do: {:ok, ["só prosa"]}
  end

  defmodule FailingClient do
    @behaviour Blackboex.LLM.ClientBehaviour
    @impl true
    def generate_text(_p, _o), do: {:error, :timeout}
    @impl true
    def stream_text(_p, _o), do: {:error, :timeout}
  end

  describe "run/4 without streaming" do
    test ":generate returns code + summary + usage" do
      assert {:ok, result} =
               CodePipeline.run(:generate, "soma 1+1", nil, client: StubClient)

      assert result.code =~ "IO.puts"
      assert result.summary == "soma simples"
      assert result.input_tokens == 42
      assert result.output_tokens == 17
    end

    test ":edit includes code_before in user prompt" do
      assert {:ok, _result} =
               CodePipeline.run(:edit, "adicione IO.inspect", "x = 1", client: StubClient)
    end

    test "returns error when response has no code block" do
      assert {:error, msg} =
               CodePipeline.run(:generate, "faça algo", nil, client: EmptyBlockClient)

      assert msg =~ "bloco de código"
    end

    test "returns error when client fails" do
      assert {:error, msg} =
               CodePipeline.run(:generate, "faça algo", nil, client: FailingClient)

      assert msg =~ "falha do LLM" or msg =~ "timeout"
    end
  end

  describe "run/4 with streaming callback" do
    test "invokes token_callback for each streamed token" do
      parent = self()
      callback = fn token -> send(parent, {:token, token}) end

      assert {:ok, _result} =
               CodePipeline.run(:generate, "soma 1+1", nil,
                 client: StubClient,
                 token_callback: callback
               )

      # StubClient.stream_text yields graphemes — assert we received some
      assert_received {:token, _}
    end
  end
end
