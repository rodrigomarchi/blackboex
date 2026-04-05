defmodule Blackboex.LLM.StreamHandlerTest do
  use ExUnit.Case, async: true

  import Mox

  @moduletag :unit

  alias Blackboex.LLM.StreamHandler

  setup :verify_on_exit!

  # Build a ReqLLM.StreamResponse with the given list of text tokens
  defp make_stream_response(tokens) do
    chunks = Enum.map(tokens, &ReqLLM.StreamChunk.text/1)
    stream = Stream.map(chunks, & &1)

    {:ok, metadata_handle} =
      ReqLLM.StreamResponse.MetadataHandle.start_link(fn -> %{finish_reason: :stop} end)

    %ReqLLM.StreamResponse{
      stream: stream,
      metadata_handle: metadata_handle,
      cancel: fn -> :ok end,
      model: nil,
      context: nil
    }
  end

  # ---------------------------------------------------------------------------
  # start/3 — plain enumerable stream path
  # ---------------------------------------------------------------------------

  describe "start/3 — plain enumerable stream" do
    test "sends token events to the caller" do
      tokens = ["Hello", " ", "World"]
      stream = Stream.map(tokens, &{:token, &1})

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts ->
        {:ok, stream}
      end)

      caller = self()
      StreamHandler.start(caller, "test prompt", system: "test")

      for token <- tokens do
        assert_receive {:llm_token, ^token}, 1000
      end

      assert_receive {:llm_done, result}, 1000
      assert result == "Hello World"
    end

    test "accumulates all tokens into the done message" do
      tokens = ["one", "two", "three"]
      stream = Stream.map(tokens, &{:token, &1})

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts -> {:ok, stream} end)

      StreamHandler.start(self(), "prompt", [])

      assert_receive {:llm_token, "one"}, 1000
      assert_receive {:llm_token, "two"}, 1000
      assert_receive {:llm_token, "three"}, 1000
      assert_receive {:llm_done, "onetwothree"}, 1000
    end

    test "sends done with empty string for empty stream" do
      empty_stream = Stream.map([], & &1)

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts -> {:ok, empty_stream} end)

      StreamHandler.start(self(), "prompt", [])

      assert_receive {:llm_done, ""}, 1000
    end

    @tag :capture_log
    test "sends error event on LLM failure" do
      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts ->
        {:error, :api_error}
      end)

      caller = self()
      StreamHandler.start(caller, "test prompt", [])

      assert_receive {:llm_error, :api_error}, 1000
    end

    @tag :capture_log
    test "sends error event with complex error reason" do
      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts ->
        {:error, %{status: 429, message: "rate limited"}}
      end)

      StreamHandler.start(self(), "prompt", [])

      assert_receive {:llm_error, %{status: 429}}, 1000
    end

    test "passes prompt and opts to the client" do
      stream = Stream.map(["ok"], &{:token, &1})

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn prompt, opts ->
        assert prompt == "my prompt"
        assert opts[:system] == "you are helpful"
        {:ok, stream}
      end)

      StreamHandler.start(self(), "my prompt", system: "you are helpful")

      assert_receive {:llm_done, _}, 1000
    end
  end

  # ---------------------------------------------------------------------------
  # start/3 — ReqLLM.StreamResponse path
  # ---------------------------------------------------------------------------

  describe "start/3 — ReqLLM.StreamResponse path" do
    test "sends token events from StreamResponse" do
      tokens = ["Foo", " ", "Bar"]
      stream_response = make_stream_response(tokens)

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts ->
        {:ok, stream_response}
      end)

      StreamHandler.start(self(), "prompt", [])

      assert_receive {:llm_token, "Foo"}, 1000
      assert_receive {:llm_token, " "}, 1000
      assert_receive {:llm_token, "Bar"}, 1000
      assert_receive {:llm_done, "Foo Bar"}, 1000
    end

    test "accumulates all tokens into the done message via StreamResponse" do
      tokens = ["Hello", " ", "from", " ", "stream"]
      stream_response = make_stream_response(tokens)

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts -> {:ok, stream_response} end)

      StreamHandler.start(self(), "prompt", [])

      Enum.each(tokens, fn token ->
        assert_receive {:llm_token, ^token}, 1000
      end)

      assert_receive {:llm_done, full}, 1000
      assert full == Enum.join(tokens)
    end

    test "sends done with empty string for StreamResponse with no content chunks" do
      # Build a StreamResponse with only a meta chunk (no :content chunks)
      chunks = [ReqLLM.StreamChunk.meta(%{finish_reason: "stop"})]
      stream = Stream.map(chunks, & &1)

      {:ok, metadata_handle} =
        ReqLLM.StreamResponse.MetadataHandle.start_link(fn -> %{} end)

      stream_response = %ReqLLM.StreamResponse{
        stream: stream,
        metadata_handle: metadata_handle,
        cancel: fn -> :ok end,
        model: nil,
        context: nil
      }

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts -> {:ok, stream_response} end)

      StreamHandler.start(self(), "prompt", [])

      # No :llm_token messages expected (meta chunk is filtered out)
      refute_receive {:llm_token, _}, 200
      assert_receive {:llm_done, ""}, 1000
    end

    test "StreamResponse with thinking chunks — thinking tokens are not forwarded" do
      chunks = [
        ReqLLM.StreamChunk.thinking("internal reasoning"),
        ReqLLM.StreamChunk.text("actual answer")
      ]

      stream = Stream.map(chunks, & &1)

      {:ok, metadata_handle} =
        ReqLLM.StreamResponse.MetadataHandle.start_link(fn -> %{} end)

      stream_response = %ReqLLM.StreamResponse{
        stream: stream,
        metadata_handle: metadata_handle,
        cancel: fn -> :ok end,
        model: nil,
        context: nil
      }

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts -> {:ok, stream_response} end)

      StreamHandler.start(self(), "prompt", [])

      # Only the :content chunk yields an :llm_token
      assert_receive {:llm_token, "actual answer"}, 1000
      refute_receive {:llm_token, "internal reasoning"}, 200
      assert_receive {:llm_done, "actual answer"}, 1000
    end
  end

  # ---------------------------------------------------------------------------
  # start/3 — return value
  # ---------------------------------------------------------------------------

  describe "start/3 — return value" do
    test "returns {:ok, pid}" do
      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts -> {:ok, []} end)

      assert {:ok, pid} = StreamHandler.start(self(), "prompt", [])
      assert is_pid(pid)
      # Wait for the async task to finish so Mox can verify the expectation
      assert_receive {:llm_done, _}, 1000
    end
  end
end
