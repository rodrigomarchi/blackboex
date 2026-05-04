defmodule Blackboex.FlowAgent.StreamManagerTest do
  use ExUnit.Case, async: true

  alias Blackboex.FlowAgent.StreamManager

  setup do
    run_id = "run-" <> Integer.to_string(System.unique_integer([:positive]))
    flow_id = "flow-" <> Integer.to_string(System.unique_integer([:positive]))
    :ok = Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:run:#{run_id}")
    :ok = Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:flow:#{flow_id}")
    %{run_id: run_id, flow_id: flow_id}
  end

  describe "build_token_callback/1" do
    test "returns a 1-arity function", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      assert is_function(cb, 1)
    end

    test "tokens before opening fence are NOT broadcast", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("Thinking...")
      cb.(" preparando JSON...")

      refute_receive {:definition_delta, _}, 100
    end

    test "broadcasts tokens after opening ~~~json fence", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~json\n")
      cb.(~s({"version":"1.0","nodes":[],"edges":[]}\n))

      assert_receive {:definition_delta, %{delta: delta, run_id: rid}}, 500
      assert rid == run_id
      assert delta =~ ~s("version")
    end

    test "buffers until newline or ≥20 chars (small token not flushed immediately)",
         %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~json\n")
      cb.("{")

      refute_receive {:definition_delta, _}, 100
    end

    test "stops broadcasting once closing fence arrives", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~json\n{\"x\":1}\n~~~\n")
      # drain any pending delta
      _ = receive_all_deltas(100)
      cb.("Summary: done")

      refute_receive {:definition_delta, _}, 100
    end
  end

  describe "flush_remaining/1" do
    test "emits pending buffer when inside the fence", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~json\n")
      # small chunk below flush threshold, no newline — stays buffered
      cb.("{")
      refute_receive {:definition_delta, _}, 50

      :ok = StreamManager.flush_remaining(run_id)
      assert_receive {:definition_delta, %{delta: "{"}}, 200
    end

    test "is a noop when no fence was opened", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("no fence yet")
      :ok = StreamManager.flush_remaining(run_id)
      refute_receive {:definition_delta, _}, 100
    end
  end

  describe "broadcasts" do
    test "broadcast_run publishes to flow_agent:run:{id}", %{run_id: run_id} do
      StreamManager.broadcast_run(run_id, {:custom, :hello})
      assert_receive {:custom, :hello}, 200
    end

    test "broadcast_flow publishes to flow_agent:flow:{id}", %{flow_id: flow_id} do
      StreamManager.broadcast_flow(flow_id, {:custom, :world})
      assert_receive {:custom, :world}, 200
    end
  end

  describe "explain mode streaming" do
    test "emits :explain_delta once threshold reached with no fence", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      # Push > 40 bytes of prose without a fence — manager commits to explain mode.
      cb.("Answer: this flow receives an event and validates the signature.\n")

      assert_receive {:explain_delta, %{delta: delta, run_id: ^run_id}}, 500
      # The `Answer:` prefix is stripped.
      refute delta =~ "Answer:"
      assert delta =~ "this flow"
    end

    test "emits :explain_delta for prose without Answer: prefix", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)

      cb.("The flow simply passes received data forward and returns.\n")

      assert_receive {:explain_delta, %{delta: delta}}, 500
      assert delta =~ "passes received data"
    end

    test "does not emit :explain_delta while under threshold", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("hi")

      refute_receive {:explain_delta, _}, 100
    end

    test "does not emit :definition_delta in explain mode", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)

      cb.("Answer: this is a prose response with a generous size.\n")

      refute_receive {:definition_delta, _}, 150
    end

    test "flush_remaining emits pending buffer in explain mode", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("Answer: start of a very long response for traversal.")
      # drain anything flushed so far
      _ = receive_all_deltas(50)

      cb.("xyz")
      :ok = StreamManager.flush_remaining(run_id)
      assert_receive {:explain_delta, %{delta: "xyz"}}, 200
    end
  end

  describe "resilience" do
    test "tokens split inside the opening fence header still trigger the transition",
         %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~")
      cb.("~json\n")
      cb.("{\"a\":1}\n")
      assert_receive {:definition_delta, %{delta: delta}}, 500
      assert delta =~ "\"a\""
    end
  end

  defp receive_all_deltas(ms) do
    receive do
      {:definition_delta, _} -> receive_all_deltas(ms)
    after
      ms -> :ok
    end
  end
end
