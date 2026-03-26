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

  describe "fallback_system_prompt/0" do
    test "instructs full code return" do
      system = EditPrompts.fallback_system_prompt()

      assert system =~ "COMPLETE"
      assert system =~ "elixir"
    end
  end

  describe "parse_response/1" do
    test "extracts search/replace blocks" do
      response = """
      Added error handling.

      <<<<<<< SEARCH
      def handle(params) do
        params
      end
      =======
      def handle(params) do
        case validate(params) do
          {:ok, data} -> data
          {:error, msg} -> %{error: msg}
        end
      end
      >>>>>>> REPLACE
      """

      assert {:ok, :search_replace, blocks, explanation} = EditPrompts.parse_response(response)
      assert length(blocks) == 1
      assert hd(blocks).search =~ "def handle(params)"
      assert hd(blocks).replace =~ "validate(params)"
      assert explanation =~ "error handling"
    end

    test "extracts multiple search/replace blocks" do
      response = """
      Updated two functions.

      <<<<<<< SEARCH
      def foo, do: 1
      =======
      def foo, do: 2
      >>>>>>> REPLACE

      <<<<<<< SEARCH
      def bar, do: 3
      =======
      def bar, do: 4
      >>>>>>> REPLACE
      """

      assert {:ok, :search_replace, blocks, _} = EditPrompts.parse_response(response)
      assert length(blocks) == 2
    end

    test "falls back to full code block when no search/replace" do
      response = """
      Here's the updated code:

      ```elixir
      def handle(params) do
        %{result: params["value"] * 2}
      end
      ```

      I added the multiplication logic.
      """

      assert {:ok, :full_code, code, explanation} = EditPrompts.parse_response(response)
      assert code =~ "def handle(params)"
      assert explanation =~ "multiplication"
    end

    test "returns error for empty response" do
      assert {:error, :no_changes_found} = EditPrompts.parse_response("")
    end

    test "returns error for response without code or blocks" do
      assert {:error, :no_changes_found} =
               EditPrompts.parse_response("I don't know how to help with that.")
    end
  end

  describe "build_search_retry_prompt/3" do
    test "includes the failed search block" do
      prompt =
        EditPrompts.build_search_retry_prompt(
          "def handle(p), do: p",
          "Add validation",
          "def handle(params) do"
        )

      assert prompt =~ "did not match"
      assert prompt =~ "def handle(params) do"
      assert prompt =~ "Add validation"
    end
  end
end
