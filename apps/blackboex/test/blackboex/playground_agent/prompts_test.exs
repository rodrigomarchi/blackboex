defmodule Blackboex.PlaygroundAgent.PromptsTest do
  use ExUnit.Case, async: true

  alias Blackboex.PlaygroundAgent.Prompts

  describe "system_prompt/1" do
    test ":generate includes allowlist modules and helper aliases" do
      prompt = Prompts.system_prompt(:generate)
      assert prompt =~ "Blackboex Playground"
      assert prompt =~ "Blackboex.Playgrounds.Http"
      assert prompt =~ "Blackboex.Playgrounds.Api"
      assert prompt =~ "Enum"
      assert prompt =~ "Jason"
      assert prompt =~ "FORBIDDEN"
      assert prompt =~ "defmodule"
      assert prompt =~ "Summary:"
    end

    test ":edit includes preservation rules" do
      prompt = Prompts.system_prompt(:edit)
      assert prompt =~ "EDITS"
      assert prompt =~ "Preserve"
      assert prompt =~ "diffs"
    end
  end

  describe "user_message/3" do
    test ":generate contains only the user request" do
      msg = Prompts.user_message(:generate, "soma 1+1", nil)
      assert msg =~ "User request"
      assert msg =~ "soma 1+1"
      refute msg =~ "Current code"
    end

    test ":edit includes current code and user request" do
      msg = Prompts.user_message(:edit, "add an IO.puts", "x = 1\nx + 1")
      assert msg =~ "Current code"
      assert msg =~ "x = 1"
      assert msg =~ "add an IO.puts"
    end

    test ":edit handles nil code_before safely" do
      msg = Prompts.user_message(:edit, "do something", nil)
      assert msg =~ "Current code"
      assert msg =~ "do something"
    end

    test "renders thread history when provided" do
      history = [
        %{role: "user", content: "how do I print something?"},
        %{role: "assistant", content: "use IO.puts/1"}
      ]

      msg = Prompts.user_message(:edit, "example", "x = 1", history: history)
      assert msg =~ "Conversation history"
      assert msg =~ "User: how do I print something?"
      assert msg =~ "Assistant: use IO.puts/1"
      assert msg =~ "User request:\nexample"
    end

    test "truncates long history messages to keep prompt bounded" do
      long = String.duplicate("a", 1000)
      history = [%{role: "user", content: long}]
      msg = Prompts.user_message(:generate, "go", nil, history: history)
      assert msg =~ "Conversation history"
      assert msg =~ "..."
      refute msg =~ String.duplicate("a", 600)
    end

    test "no history block when history is empty" do
      msg = Prompts.user_message(:generate, "go", nil, history: [])
      refute msg =~ "Conversation history"
    end
  end
end
