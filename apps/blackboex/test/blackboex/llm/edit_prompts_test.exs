defmodule Blackboex.LLM.EditPromptsTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.LLM.EditPrompts

  describe "build_edit_prompt/3" do
    test "includes current code in the message" do
      current_code = "def handle(params), do: %{result: params}"
      instruction = "Add input validation"
      history = []

      prompt = EditPrompts.build_edit_prompt(current_code, instruction, history)

      assert prompt =~ current_code
    end

    test "includes the user instruction" do
      current_code = "def handle(params), do: params"
      instruction = "Add authentication check"
      history = []

      prompt = EditPrompts.build_edit_prompt(current_code, instruction, history)

      assert prompt =~ "Add authentication check"
    end

    test "includes last 10 messages from history" do
      current_code = "def handle(params), do: params"
      instruction = "Add validation"

      history =
        for i <- 1..15 do
          %{"role" => "user", "content" => "Message #{i}"}
        end

      prompt = EditPrompts.build_edit_prompt(current_code, instruction, history)

      # Should include messages 6-15 (last 10)
      refute prompt =~ "Message 1\n"
      refute prompt =~ "Message 5\n"
      assert prompt =~ "Message 6"
      assert prompt =~ "Message 15"
    end

    test "includes history when 10 or fewer messages" do
      current_code = "def handle(params), do: params"
      instruction = "Fix bug"

      history = [
        %{"role" => "user", "content" => "Create a todo API"},
        %{"role" => "assistant", "content" => "Here is the code"}
      ]

      prompt = EditPrompts.build_edit_prompt(current_code, instruction, history)

      assert prompt =~ "Create a todo API"
      assert prompt =~ "Here is the code"
    end
  end

  describe "system_prompt/0" do
    test "instructs full-file replacement (not diff)" do
      system = EditPrompts.system_prompt()

      assert system =~ "COMPLETE" || system =~ "complete" || system =~ "full"
      assert system =~ "code"
    end

    test "includes security constraints from base prompts" do
      system = EditPrompts.system_prompt()

      # Must prohibit dangerous modules
      assert system =~ "File"
      assert system =~ "System"
      assert system =~ "IO"
      assert system =~ "Code"
      assert system =~ "Process"

      # Must enforce handler rules
      assert system =~ "conn" || system =~ "Plug"
      assert system =~ "def"
    end
  end

  describe "parse_response/1" do
    test "extracts code from markdown code block" do
      response = """
      Here's the updated code:

      ```elixir
      def handle(params) do
        %{result: params["value"] * 2}
      end
      ```

      I added the multiplication logic.
      """

      assert {:ok, code, explanation} = EditPrompts.parse_response(response)
      assert code =~ "def handle(params)"
      assert code =~ "params[\"value\"] * 2"
      assert explanation =~ "multiplication"
    end

    test "extracts code from code block without language specifier" do
      response = """
      Updated:

      ```
      def handle(params), do: %{ok: true}
      ```
      """

      assert {:ok, code, _explanation} = EditPrompts.parse_response(response)
      assert code =~ "def handle(params)"
    end

    test "extracts explanation from text outside code block" do
      response = """
      I've added input validation to check that the required fields are present.

      ```elixir
      def handle(params) do
        %{validated: true}
      end
      ```

      This ensures the API rejects invalid input.
      """

      assert {:ok, _code, explanation} = EditPrompts.parse_response(response)
      assert explanation =~ "validation"
    end

    test "returns error if no code block found" do
      response = "I'm not sure what you mean, could you clarify?"

      assert {:error, :no_code_found} = EditPrompts.parse_response(response)
    end

    test "returns error for empty response" do
      assert {:error, :no_code_found} = EditPrompts.parse_response("")
    end
  end
end
