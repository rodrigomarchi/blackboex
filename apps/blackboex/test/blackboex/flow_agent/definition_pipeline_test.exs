defmodule Blackboex.FlowAgent.DefinitionPipelineTest do
  use ExUnit.Case, async: true

  import Mox

  alias Blackboex.FlowAgent.DefinitionPipeline

  setup :verify_on_exit!
  setup :set_mox_from_context

  @minimal_flow %{
    "version" => "1.0",
    "nodes" => [
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 50, "y" => 250},
        "data" => %{}
      },
      %{
        "id" => "n2",
        "type" => "end",
        "position" => %{"x" => 250, "y" => 250},
        "data" => %{}
      }
    ],
    "edges" => [
      %{
        "id" => "e1",
        "source" => "n1",
        "source_port" => 0,
        "target" => "n2",
        "target_port" => 0
      }
    ]
  }

  defp fenced(flow), do: "~~~json\n#{Jason.encode!(flow)}\n~~~\n\nSummary: ready."

  defp stub_llm_generate(content, usage \\ %{input_tokens: 10, output_tokens: 20}) do
    stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
      stream =
        [{:token, content}]
        |> Stream.map(& &1)

      {:ok, stream}
    end)

    stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
      {:ok, %{content: content, usage: usage}}
    end)
  end

  describe "run/4 happy path — edit mode" do
    test "returns {:ok, %{kind: :edit, definition, summary}} when LLM yields valid JSON" do
      stub_llm_generate(fenced(@minimal_flow))

      token_cb = fn _ -> :ok end

      assert {:ok, result} =
               DefinitionPipeline.run(
                 :generate,
                 "create a hello world flow",
                 nil,
                 token_callback: token_cb,
                 client: Blackboex.LLM.ClientMock
               )

      assert result.kind == :edit
      assert result.definition == @minimal_flow
      assert result.summary == "ready."
      assert result.input_tokens >= 0
      assert result.output_tokens >= 0
    end
  end

  describe "run/4 happy path — explain mode" do
    test "returns {:ok, %{kind: :explain, answer}} when LLM answers a question" do
      stub_llm_generate("Answer: This flow receives an event and validates it.")

      assert {:ok, result} =
               DefinitionPipeline.run(
                 :edit,
                 "explain how this flow works",
                 %{"version" => "1.0", "nodes" => [], "edges" => []},
                 client: Blackboex.LLM.ClientMock
               )

      assert result.kind == :explain
      assert result.answer == "This flow receives an event and validates it."
    end

    test "accepts prose without Answer: prefix as a fallback" do
      stub_llm_generate("The flow validates the received event and returns the status.")

      assert {:ok, %{kind: :explain, answer: answer}} =
               DefinitionPipeline.run(
                 :edit,
                 "explain the flow",
                 %{"version" => "1.0", "nodes" => [], "edges" => []},
                 client: Blackboex.LLM.ClientMock
               )

      assert answer =~ "validates the received event"
    end
  end

  describe "run/4 error paths" do
    test "LLM returns empty content → {:error, :no_content}" do
      stub_llm_generate("   \n   ")

      assert {:error, :no_content} =
               DefinitionPipeline.run(:generate, "hi", nil, client: Blackboex.LLM.ClientMock)
    end

    test "LLM returns invalid JSON → {:error, {:invalid_json, _}}" do
      stub_llm_generate("~~~json\n{not valid\n~~~")

      assert {:error, {:invalid_json, _}} =
               DefinitionPipeline.run(:generate, "hi", nil, client: Blackboex.LLM.ClientMock)
    end

    test "LLM returns JSON that fails BlackboexFlow.validate → {:error, {:invalid_flow, _}}" do
      bad = %{"version" => "9.99", "nodes" => [], "edges" => []}
      stub_llm_generate(fenced(bad))

      assert {:error, {:invalid_flow, _reason}} =
               DefinitionPipeline.run(:generate, "oi", nil, client: Blackboex.LLM.ClientMock)
    end

    test "LLM failure propagates as {:error, reason}" do
      stub(Blackboex.LLM.ClientMock, :stream_text, fn _prompt, _opts ->
        {:error, :timeout}
      end)

      stub(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:error, :timeout}
      end)

      assert {:error, _reason} =
               DefinitionPipeline.run(:generate, "oi", nil, client: Blackboex.LLM.ClientMock)
    end
  end

  describe "run/4 auto-layout integration" do
    test "applies AutoLayout when LLM omits positions, then validates" do
      missing_positions = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "data" => %{}},
          %{"id" => "n2", "type" => "end", "data" => %{}}
        ],
        "edges" => [
          %{
            "id" => "e1",
            "source" => "n1",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          }
        ]
      }

      stub_llm_generate(fenced(missing_positions))

      assert {:ok, result} =
               DefinitionPipeline.run(:generate, "oi", nil, client: Blackboex.LLM.ClientMock)

      for node <- result.definition["nodes"] do
        assert %{"x" => _, "y" => _} = node["position"]
      end
    end
  end
end
