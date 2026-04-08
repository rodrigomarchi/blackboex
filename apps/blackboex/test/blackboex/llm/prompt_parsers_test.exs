defmodule Blackboex.LLM.PromptParsersTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.LLM.PromptParsers

  # ── parse_code_block/1 ────────────────────────────────────────

  describe "parse_code_block/1" do
    test "extracts code from elixir code block" do
      response = """
      Here's the code:

      ```elixir
      def handle(params), do: params
      ```
      """

      assert {:ok, code} = PromptParsers.parse_code_block(response)
      assert code =~ "def handle(params)"
    end

    test "extracts code from plain code block" do
      response = """
      ```
      def handle(params), do: params
      ```
      """

      assert {:ok, code} = PromptParsers.parse_code_block(response)
      assert code =~ "def handle(params)"
    end

    test "returns error for no code block" do
      assert {:error, :no_code_found} = PromptParsers.parse_code_block("just text")
    end

    test "returns error for empty string" do
      assert {:error, :no_code_found} = PromptParsers.parse_code_block("")
    end

    test "trims whitespace from extracted code" do
      response = "```elixir\n  def foo, do: :ok\n```"
      assert {:ok, code} = PromptParsers.parse_code_block(response)
      assert code == "def foo, do: :ok"
    end

    test "handles Windows line endings" do
      response = "```elixir\r\ndef handle(p), do: p\r\n```"
      assert {:ok, code} = PromptParsers.parse_code_block(response)
      assert code =~ "def handle"
    end
  end

  # ── parse_search_replace_blocks/1 ─────────────────────────────

  describe "parse_search_replace_blocks/1" do
    test "parses a single SEARCH/REPLACE block" do
      response = """
      <<<<<<< SEARCH
      def handle(params) do
        params
      end
      =======
      def handle(params) do
        Map.put(params, "processed", true)
      end
      >>>>>>> REPLACE
      """

      blocks = PromptParsers.parse_search_replace_blocks(response)

      assert length(blocks) == 1
      [block] = blocks
      assert block.search =~ "def handle(params) do\n  params\nend"
      assert block.replace =~ "Map.put(params, \"processed\", true)"
    end

    test "parses multiple blocks" do
      response = """
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

      blocks = PromptParsers.parse_search_replace_blocks(response)
      assert length(blocks) == 2
    end

    test "returns empty list when no blocks found" do
      assert PromptParsers.parse_search_replace_blocks("no blocks here") == []
    end

    test "handles empty replacement (deletion)" do
      response = """
      <<<<<<< SEARCH
      @doc "Remove this"
      =======
      >>>>>>> REPLACE
      """

      [block] = PromptParsers.parse_search_replace_blocks(response)
      assert block.search =~ "Remove this"
      assert block.replace == ""
    end

    test "strips trailing newlines" do
      response = "<<<<<<< SEARCH\nfoo\n=======\nbar\n>>>>>>> REPLACE"

      [block] = PromptParsers.parse_search_replace_blocks(response)
      refute String.ends_with?(block.search, "\n")
      refute String.ends_with?(block.replace, "\n")
    end

    test "handles Windows line endings" do
      response =
        "<<<<<<< SEARCH\r\ndef old, do: 1\r\n=======\r\ndef new, do: 2\r\n>>>>>>> REPLACE"

      [block] = PromptParsers.parse_search_replace_blocks(response)
      assert block.search == "def old, do: 1"
      assert block.replace == "def new, do: 2"
    end
  end

  # ── parse_test_fix_edits/1 ────────────────────────────────────

  describe "parse_test_fix_edits/1" do
    test "parses both CODE and TESTS sections" do
      response = """
      ---CODE---
      <<<<<<< SEARCH
      def handle(p), do: p
      =======
      def handle(p), do: Map.put(p, "ok", true)
      >>>>>>> REPLACE

      ---TESTS---
      <<<<<<< SEARCH
      assert result == %{}
      =======
      assert result == %{"ok" => true}
      >>>>>>> REPLACE
      """

      {code_edits, test_edits} = PromptParsers.parse_test_fix_edits(response)
      assert length(code_edits) == 1
      assert length(test_edits) == 1
    end

    test "returns :error when neither section has edits" do
      assert :error = PromptParsers.parse_test_fix_edits("no sections")
    end

    test "returns :error for empty string" do
      assert :error = PromptParsers.parse_test_fix_edits("")
    end
  end

  # ── parse_code_and_tests/1 ────────────────────────────────────

  describe "parse_code_and_tests/1" do
    test "parses both sections with full code" do
      response = """
      ---CODE---
      def handle(params), do: params
      ---TESTS---
      defmodule HandlerTest do
        use ExUnit.Case
      end
      """

      {code, tests} = PromptParsers.parse_code_and_tests(response)
      assert code =~ "def handle(params)"
      assert tests =~ "defmodule HandlerTest"
    end

    test "returns :error when sections missing" do
      assert :error = PromptParsers.parse_code_and_tests("")
      assert :error = PromptParsers.parse_code_and_tests("just text")
    end
  end

  # ── sanitize_code_fence/1 ─────────────────────────────────────

  describe "sanitize_code_fence/1" do
    test "escapes triple backticks" do
      assert PromptParsers.sanitize_code_fence("before ``` after") == "before ` ` ` after"
    end

    test "handles text without backticks" do
      assert PromptParsers.sanitize_code_fence("clean text") == "clean text"
    end
  end

  # ── sanitize_field/1 ──────────────────────────────────────────

  describe "sanitize_field/1" do
    test "strips backticks and caps length" do
      result = PromptParsers.sanitize_field("hello `world`")
      refute result =~ "`"
    end

    test "truncates at 10_000 characters" do
      long = String.duplicate("a", 20_000)
      result = PromptParsers.sanitize_field(long)
      assert String.length(result) == 10_000
    end
  end
end
