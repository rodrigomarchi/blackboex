defmodule Blackboex.LLM.StreamHandlerTest do
  use ExUnit.Case, async: true

  import Mox

  @moduletag :unit

  alias Blackboex.LLM.StreamHandler

  setup :verify_on_exit!

  describe "start/3" do
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
  end
end
