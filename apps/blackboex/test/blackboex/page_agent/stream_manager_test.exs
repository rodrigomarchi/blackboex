defmodule Blackboex.PageAgent.StreamManagerTest do
  use ExUnit.Case, async: false

  @moduletag :unit

  alias Blackboex.PageAgent.StreamManager

  setup do
    run_id = Ecto.UUID.generate()
    topic = "page_agent:run:#{run_id}"
    Phoenix.PubSub.subscribe(Blackboex.PubSub, topic)
    %{run_id: run_id, topic: topic}
  end

  describe "build_token_callback/1" do
    test "returns a function, initial state is :before_fence", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      assert is_function(cb, 1)
      assert Process.get(:pg_page_stream_state) == :before_fence
    end
  end

  describe "state machine" do
    test "buffers tokens before the fence and does not broadcast", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("Some prose ")
      cb.("before the fence. ")
      refute_receive {:content_delta, _}, 50
    end

    test "emits tokens inside ~~~markdown fence as :content_delta", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~markdown\n")
      cb.("# Hello world, this is a long enough chunk to flush.\n")

      assert_receive {:content_delta, %{delta: delta, run_id: ^run_id}}, 100
      assert delta =~ "# Hello world"
    end

    test "stops emitting after closing ~~~", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~markdown\n")
      cb.("content line one, long enough to force a flush.\n")

      assert_receive {:content_delta, _}, 100

      cb.("\n~~~\n")
      cb.("Resumo: did it.")

      # Drain any in-flight deltas but assert the Resumo text never leaks.
      Process.sleep(50)

      received_resumo? =
        receive do
          {:content_delta, %{delta: delta}} -> String.contains?(delta, "Resumo")
        after
          0 -> false
        end

      refute received_resumo?
    end

    test "accepts ~~~md alias as opening fence", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~md\n")
      cb.("# content line one, long enough to force a flush.\n")

      assert_receive {:content_delta, %{delta: delta}}, 100
      assert delta =~ "content line one"
    end

    test "accepts plain ~~~ fence without language", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~\n")
      cb.("this is a line of content, long enough to force a flush.\n")

      assert_receive {:content_delta, %{delta: delta}}, 100
      assert delta =~ "line of content"
    end

    test "accepts ```markdown backtick fence (LLM default fallback)", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("```markdown\n")
      cb.("# backtick streaming, long enough to force a flush.\n")

      assert_receive {:content_delta, %{delta: delta}}, 100
      assert delta =~ "backtick streaming"
    end
  end

  describe "flush_remaining/1" do
    test "emits buffered partial line at end of stream", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~markdown\n")
      # short, no newline — stays buffered
      cb.("tiny")
      refute_receive {:content_delta, _}, 50

      StreamManager.flush_remaining(run_id)
      assert_receive {:content_delta, %{delta: "tiny"}}, 100
    end

    test "is a no-op when there is no buffered content", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~markdown\n")
      StreamManager.flush_remaining(run_id)
      refute_receive {:content_delta, _}, 50
    end

    test "does not emit after the fence has closed", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("~~~markdown\nfoo\n~~~\n")
      cb.("Resumo: ok")
      StreamManager.flush_remaining(run_id)
      # Whatever we got was from inside the fence; Resumo must not appear.
      Process.sleep(20)
      refute_receive {:content_delta, %{delta: "Resumo: ok"}}, 0
    end
  end

  describe "broadcast helpers" do
    test "broadcast_run/2 publishes on the per-run topic", %{run_id: run_id} do
      StreamManager.broadcast_run(run_id, {:run_started, %{run_id: run_id}})
      assert_receive {:run_started, %{run_id: ^run_id}}, 100
    end

    test "broadcast_page/3 publishes on the org-scoped page topic" do
      org_id = Ecto.UUID.generate()
      page_id = Ecto.UUID.generate()
      Phoenix.PubSub.subscribe(Blackboex.PubSub, StreamManager.page_topic(org_id, page_id))
      StreamManager.broadcast_page(org_id, page_id, {:run_started, %{page_id: page_id}})
      assert_receive {:run_started, %{page_id: ^page_id}}, 100
    end
  end
end
