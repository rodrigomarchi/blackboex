defmodule Blackboex.LLM.EditPromptsTest do
  use ExUnit.Case, async: true

  alias Blackboex.LLM.EditPrompts

  describe "build_edit_prompt/3" do
    test "includes current code and instruction" do
      prompt =
        EditPrompts.build_edit_prompt(
          "def handle(params), do: params",
          "Add authentication check",
          []
        )

      assert prompt =~ "def handle(params), do: params"
      assert prompt =~ "Add authentication check"
    end

    test "includes last 10 messages from history" do
      history = for i <- 1..15, do: %{"role" => "user", "content" => "Message #{i}"}

      prompt =
        EditPrompts.build_edit_prompt("def handle(p), do: p", "Add validation", history)

      refute prompt =~ "Message 1\n"
      refute prompt =~ "Message 5\n"
      assert prompt =~ "Message 6"
      assert prompt =~ "Message 15"
    end
  end

  describe "system_prompt/0" do
    test "instructs search/replace format" do
      system = EditPrompts.system_prompt()

      assert system =~ "SEARCH/REPLACE"
      assert system =~ "SEARCH"
      assert system =~ "REPLACE"
    end

    test "includes security constraints from base prompts" do
      system = EditPrompts.system_prompt()

      assert system =~ "File"
      assert system =~ "System"
      assert system =~ "IO"
      assert system =~ "Code"
      assert system =~ "Process"
      assert system =~ "conn" || system =~ "Plug"
    end
  end
end
