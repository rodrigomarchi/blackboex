defmodule Blackboex.PageAgent.ContentPipelineTest do
  use ExUnit.Case, async: false

  @moduletag :unit

  alias Blackboex.PageAgent.ContentPipeline

  defp start_recording_client do
    case Process.whereis(__MODULE__.RecordingClient) do
      nil -> __MODULE__.RecordingClient.start()
      pid -> {:ok, pid}
    end
  end

  defmodule StubClient do
    @behaviour Blackboex.LLM.ClientBehaviour

    @canned """
    Aqui vai:
    ~~~markdown
    # Título

    Parágrafo de teste.
    ~~~
    Resumo: escrevi intro.
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

  defmodule RecordingClient do
    @behaviour Blackboex.LLM.ClientBehaviour

    def start, do: Agent.start_link(fn -> %{} end, name: __MODULE__)
    def last_prompt, do: Agent.get(__MODULE__, & &1)

    @impl true
    def generate_text(prompt, opts) do
      Agent.update(__MODULE__, fn _ -> %{prompt: prompt, opts: opts} end)
      {:ok, %{content: "~~~markdown\nx\n~~~\nResumo: r", usage: %{}}}
    end

    @impl true
    def stream_text(prompt, opts) do
      Agent.update(__MODULE__, fn _ -> %{prompt: prompt, opts: opts} end)
      {:ok, Stream.map(["~~~markdown\nx\n~~~"], & &1)}
    end
  end

  defmodule EmptyBlockClient do
    @behaviour Blackboex.LLM.ClientBehaviour
    @impl true
    def generate_text(_p, _o), do: {:ok, %{content: "só prosa, sem bloco", usage: %{}}}
    @impl true
    def stream_text(_p, _o), do: {:ok, ["só prosa, sem bloco"]}
  end

  defmodule FailingClient do
    @behaviour Blackboex.LLM.ClientBehaviour
    @impl true
    def generate_text(_p, _o), do: {:error, :timeout}
    @impl true
    def stream_text(_p, _o), do: {:error, :timeout}
  end

  describe "run/4 without streaming" do
    test ":generate returns content + summary + token usage" do
      assert {:ok, result} =
               ContentPipeline.run(:generate, "escreve intro", nil, client: StubClient)

      assert result.content =~ "# Título"
      assert result.summary == "escrevi intro."
      assert result.input_tokens == 42
      assert result.output_tokens == 17
    end

    test ":edit forwards content_before to the prompt" do
      start_recording_client()

      assert {:ok, _} =
               ContentPipeline.run(:edit, "muda", "conteúdo antigo", client: RecordingClient)

      %{prompt: prompt} = RecordingClient.last_prompt()
      assert prompt =~ "conteúdo antigo"
      assert prompt =~ "muda"
    end

    test "returns error when response has no content block" do
      assert {:error, msg} =
               ContentPipeline.run(:generate, "x", nil, client: EmptyBlockClient)

      assert msg =~ "bloco"
    end

    test "returns error when client fails" do
      assert {:error, msg} =
               ContentPipeline.run(:generate, "x", nil, client: FailingClient)

      assert msg =~ "timeout" or msg =~ "LLM"
    end

    test "without token_callback uses generate_text path" do
      assert {:ok, _} = ContentPipeline.run(:generate, "x", nil, client: StubClient)
    end
  end

  describe "run/4 with streaming" do
    test "invokes token_callback for each streamed token" do
      parent = self()
      callback = fn token -> send(parent, {:tok, token}) end

      assert {:ok, _} =
               ContentPipeline.run(:generate, "x", nil,
                 client: StubClient,
                 token_callback: callback
               )

      assert_received {:tok, _}
    end

    test "returns success with streamed content assembled" do
      callback = fn _ -> :ok end

      assert {:ok, result} =
               ContentPipeline.run(:generate, "x", nil,
                 client: StubClient,
                 token_callback: callback
               )

      assert result.content =~ "Título"
    end
  end

  describe "history" do
    test "forwards history option to the prompt" do
      start_recording_client()
      history = [%{role: "user", content: "pergunta antiga"}]

      assert {:ok, _} =
               ContentPipeline.run(:generate, "novo", nil,
                 client: RecordingClient,
                 history: history
               )

      %{prompt: prompt} = RecordingClient.last_prompt()
      assert prompt =~ "pergunta antiga"
      assert prompt =~ "novo"
    end
  end
end
