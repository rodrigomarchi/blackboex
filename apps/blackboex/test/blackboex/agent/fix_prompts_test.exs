defmodule Blackboex.Agent.FixPromptsTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Agent.FixPrompts

  # ──────────────────────────────────────────────────────────────
  # fix_compilation/3
  # ──────────────────────────────────────────────────────────────

  describe "fix_compilation/3" do
    test "returns {system, prompt} tuple with errors and code" do
      {system, prompt} = FixPrompts.fix_compilation("def handle(_), do: :ok", "undefined foo/0")

      assert is_binary(system)
      assert is_binary(prompt)
      assert system =~ "compilation errors"
      assert prompt =~ "def handle(_), do: :ok"
      assert prompt =~ "undefined foo/0"
    end

    test "system prompt includes edit format instructions" do
      {system, _prompt} = FixPrompts.fix_compilation("code", "error")

      assert system =~ "<<<<<<< SEARCH"
      assert system =~ "======="
      assert system =~ ">>>>>>> REPLACE"
    end

    test "includes context log when provided" do
      {_system, prompt} =
        FixPrompts.fix_compilation("code", "error", "Previous fix attempt: replaced json/2")

      assert prompt =~ "Pipeline History"
      assert prompt =~ "Previous fix attempt: replaced json/2"
    end

    test "omits context section when context_log is empty" do
      {_system, prompt} = FixPrompts.fix_compilation("code", "error", "")

      refute prompt =~ "Pipeline History"
    end

    test "omits context section when context_log is not provided (default)" do
      {_system, prompt} = FixPrompts.fix_compilation("code", "error")

      refute prompt =~ "Pipeline History"
    end

    test "system prompt includes elsif fix guidance" do
      {system, _prompt} = FixPrompts.fix_compilation("code", "error")

      assert system =~ "elsif"
      assert system =~ "cond do"
    end

    test "system prompt includes changeset/2 guidance" do
      {system, _prompt} = FixPrompts.fix_compilation("code", "error")

      assert system =~ "changeset/2"
    end

    test "handles multiline error string" do
      errors = """
      ** (CompileError) nofile:5: undefined function foo/0
      ** (CompileError) nofile:10: undefined function bar/1
      """

      {_system, prompt} = FixPrompts.fix_compilation("code", errors)

      assert prompt =~ "undefined function foo/0"
      assert prompt =~ "undefined function bar/1"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # fix_lint/3
  # ──────────────────────────────────────────────────────────────

  describe "fix_lint/3" do
    test "returns {system, prompt} tuple with issues and code" do
      {system, prompt} = FixPrompts.fix_lint("def handle(_), do: :ok", "Missing @doc")

      assert system =~ "linter issues"
      assert prompt =~ "Lint Issues"
      assert prompt =~ "Missing @doc"
      assert prompt =~ "def handle(_), do: :ok"
    end

    test "system prompt documents all linter rules" do
      {system, _prompt} = FixPrompts.fix_lint("code", "issue")

      assert system =~ "120 characters"
      assert system =~ "40 lines"
      assert system =~ "4 levels of nesting"
      assert system =~ "@doc"
      assert system =~ "@spec"
    end

    test "includes context log when provided" do
      {_system, prompt} = FixPrompts.fix_lint("code", "issue", "Attempt 1: added @doc")

      assert prompt =~ "Pipeline History"
      assert prompt =~ "Attempt 1: added @doc"
    end

    test "omits context section by default" do
      {_system, prompt} = FixPrompts.fix_lint("code", "issue")

      refute prompt =~ "Pipeline History"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # fix_tests/4
  # ──────────────────────────────────────────────────────────────

  describe "fix_tests/4" do
    test "returns {system, prompt} with all three inputs" do
      {system, prompt} =
        FixPrompts.fix_tests("handler code", "test code", "1 test failed: expected 1, got 2")

      assert system =~ "Tests failed"
      assert prompt =~ "Handler Code"
      assert prompt =~ "handler code"
      assert prompt =~ "Test Code"
      assert prompt =~ "test code"
      assert prompt =~ "1 test failed"
    end

    test "system prompt includes ---CODE--- / ---TESTS--- format" do
      {system, _prompt} = FixPrompts.fix_tests("code", "tests", "failure")

      assert system =~ "---CODE---"
      assert system =~ "---TESTS---"
    end

    test "system prompt warns about float comparison" do
      {system, _prompt} = FixPrompts.fix_tests("code", "tests", "failure")

      assert system =~ "NEVER use `==` for computed float values"
      assert system =~ "0.1"
    end

    test "system prompt includes resilience rule for deleting unfixable tests" do
      {system, _prompt} = FixPrompts.fix_tests("code", "tests", "failure")

      assert system =~ "DELETE those tests entirely"
    end

    test "system prompt prefers fixing tests over handler" do
      {system, _prompt} = FixPrompts.fix_tests("code", "tests", "failure")

      assert system =~ "Prefer fixing the TESTS over the handler code"
    end

    test "includes context log when provided" do
      {_system, prompt} =
        FixPrompts.fix_tests("code", "tests", "failure", "Fix 1: changed assertion")

      assert prompt =~ "Pipeline History"
      assert prompt =~ "Fix 1: changed assertion"
    end

    test "omits context section by default" do
      {_system, prompt} = FixPrompts.fix_tests("code", "tests", "failure")

      refute prompt =~ "Pipeline History"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # edit_code/4
  # ──────────────────────────────────────────────────────────────

  describe "edit_code/4" do
    test "returns {system, prompt} with all inputs" do
      {system, prompt} =
        FixPrompts.edit_code("base system", "add validation", "def handle(p), do: p", "tests")

      assert system =~ "base system"
      assert system =~ "modifying existing code"
      assert prompt =~ "Instruction"
      assert prompt =~ "add validation"
      assert prompt =~ "Current Code"
      assert prompt =~ "def handle(p), do: p"
      assert prompt =~ "Current Tests"
      assert prompt =~ "tests"
    end

    test "system prompt instructs to preserve existing functionality" do
      {system, _prompt} = FixPrompts.edit_code("base", "instruction", "code", "tests")

      assert system =~ "Preserve all existing functionality"
    end

    test "system prompt instructs no markdown fences" do
      {system, _prompt} = FixPrompts.edit_code("base", "instruction", "code", "tests")

      assert system =~ "No explanations, no markdown fences"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # parse_search_replace_blocks/1
  # ──────────────────────────────────────────────────────────────

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

      blocks = FixPrompts.parse_search_replace_blocks(response)

      assert length(blocks) == 1
      [block] = blocks
      assert block.search =~ "def handle(params) do\n  params\nend"
      assert block.replace =~ "Map.put(params, \"processed\", true)"
    end

    test "parses multiple SEARCH/REPLACE blocks" do
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

      blocks = FixPrompts.parse_search_replace_blocks(response)

      assert length(blocks) == 2
      assert Enum.at(blocks, 0).search =~ "def foo"
      assert Enum.at(blocks, 0).replace =~ "def foo, do: 2"
      assert Enum.at(blocks, 1).search =~ "def bar"
      assert Enum.at(blocks, 1).replace =~ "def bar, do: 4"
    end

    test "returns empty list when no blocks found" do
      assert FixPrompts.parse_search_replace_blocks("no blocks here") == []
    end

    test "returns empty list for empty string" do
      assert FixPrompts.parse_search_replace_blocks("") == []
    end

    test "handles REPLACE block with empty replacement (deletion)" do
      response = """
      <<<<<<< SEARCH
      @doc "Remove this"
      =======
      >>>>>>> REPLACE
      """

      blocks = FixPrompts.parse_search_replace_blocks(response)

      assert length(blocks) == 1
      [block] = blocks
      assert block.search =~ "Remove this"
      assert block.replace == ""
    end

    test "handles SEARCH block with special regex characters" do
      response = """
      <<<<<<< SEARCH
      %{key: "value", nested: %{a: 1}}
      =======
      %{key: "new_value", nested: %{a: 2}}
      >>>>>>> REPLACE
      """

      blocks = FixPrompts.parse_search_replace_blocks(response)

      assert length(blocks) == 1
      assert Enum.at(blocks, 0).search =~ "%{key:"
    end

    test "handles code with pipe operators and multiline expressions" do
      response = """
      <<<<<<< SEARCH
      params
      |> Map.get("items")
      |> Enum.map(&String.upcase/1)
      =======
      params
      |> Map.get("items", [])
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.upcase/1)
      >>>>>>> REPLACE
      """

      blocks = FixPrompts.parse_search_replace_blocks(response)

      assert length(blocks) == 1
      assert Enum.at(blocks, 0).replace =~ "String.trim"
    end

    test "strips trailing newline from search and replace" do
      response = "<<<<<<< SEARCH\nfoo\n=======\nbar\n>>>>>>> REPLACE"

      [block] = FixPrompts.parse_search_replace_blocks(response)

      refute String.ends_with?(block.search, "\n")
      refute String.ends_with?(block.replace, "\n")
    end

    test "preserves internal newlines in search and replace" do
      response = """
      <<<<<<< SEARCH
      line1
      line2
      line3
      =======
      new1
      new2
      >>>>>>> REPLACE
      """

      [block] = FixPrompts.parse_search_replace_blocks(response)

      assert block.search == "line1\nline2\nline3"
      assert block.replace == "new1\nnew2"
    end

    test "handles Windows line endings (\\r\\n) in SEARCH/REPLACE markers" do
      # LLMs can return \r\n — input is normalized to \n before parsing.
      response =
        "<<<<<<< SEARCH\r\ndef old, do: 1\r\n=======\r\ndef new, do: 2\r\n>>>>>>> REPLACE"

      [block] = FixPrompts.parse_search_replace_blocks(response)

      assert block.search == "def old, do: 1"
      assert block.replace == "def new, do: 2"
    end

    test "ignores text between blocks" do
      response = """
      Here's the first fix:
      <<<<<<< SEARCH
      old1
      =======
      new1
      >>>>>>> REPLACE

      And the second fix:
      <<<<<<< SEARCH
      old2
      =======
      new2
      >>>>>>> REPLACE

      Done!
      """

      blocks = FixPrompts.parse_search_replace_blocks(response)

      assert length(blocks) == 2
    end

    test "handles block where search equals replace (no-op edit)" do
      response = """
      <<<<<<< SEARCH
      same code
      =======
      same code
      >>>>>>> REPLACE
      """

      [block] = FixPrompts.parse_search_replace_blocks(response)

      assert block.search == block.replace
    end
  end

  # ──────────────────────────────────────────────────────────────
  # parse_test_fix_edits/1
  # ──────────────────────────────────────────────────────────────

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

      {code_edits, test_edits} = FixPrompts.parse_test_fix_edits(response)

      assert length(code_edits) == 1
      assert length(test_edits) == 1
      assert hd(code_edits).replace =~ "Map.put"
      assert hd(test_edits).replace =~ "ok"
    end

    test "parses CODE section only" do
      response = """
      ---CODE---
      <<<<<<< SEARCH
      def old, do: 1
      =======
      def new, do: 2
      >>>>>>> REPLACE
      """

      {code_edits, test_edits} = FixPrompts.parse_test_fix_edits(response)

      assert length(code_edits) == 1
      assert test_edits == []
    end

    test "parses TESTS section only" do
      response = """
      ---TESTS---
      <<<<<<< SEARCH
      assert result == 1
      =======
      assert result == 2
      >>>>>>> REPLACE
      """

      {code_edits, test_edits} = FixPrompts.parse_test_fix_edits(response)

      assert code_edits == []
      assert length(test_edits) == 1
    end

    test "returns :error when neither section has edits" do
      assert :error = FixPrompts.parse_test_fix_edits("no sections at all")
    end

    test "returns :error for empty string" do
      assert :error = FixPrompts.parse_test_fix_edits("")
    end

    test "returns :error when sections exist but have no SEARCH/REPLACE blocks" do
      response = """
      ---CODE---
      Just some text without edits

      ---TESTS---
      More text without edits
      """

      assert :error = FixPrompts.parse_test_fix_edits(response)
    end

    test "handles multiple edits per section" do
      response = """
      ---CODE---
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

      ---TESTS---
      <<<<<<< SEARCH
      assert foo() == 1
      =======
      assert foo() == 2
      >>>>>>> REPLACE
      """

      {code_edits, test_edits} = FixPrompts.parse_test_fix_edits(response)

      assert length(code_edits) == 2
      assert length(test_edits) == 1
    end

    test "handles ---TESTS--- appearing before ---CODE---" do
      response = """
      ---TESTS---
      <<<<<<< SEARCH
      assert x == 1
      =======
      assert x == 2
      >>>>>>> REPLACE

      ---CODE---
      <<<<<<< SEARCH
      def x, do: 1
      =======
      def x, do: 2
      >>>>>>> REPLACE
      """

      result = FixPrompts.parse_test_fix_edits(response)

      # The CODE regex looks for ---CODE--- followed by content until ---TESTS--- or $
      # If TESTS comes first, the CODE regex should still find the CODE section
      case result do
        {code_edits, test_edits} ->
          assert test_edits != []
          # CODE section might or might not be found depending on regex behavior
          assert is_list(code_edits)

        :error ->
          flunk("Should parse when sections are in reverse order")
      end
    end

    test "handles extra whitespace after section markers" do
      response = """
      ---CODE---
      <<<<<<< SEARCH
      old
      =======
      new
      >>>>>>> REPLACE
      """

      {code_edits, _test_edits} = FixPrompts.parse_test_fix_edits(response)

      # The regex uses \s* after --- marker, so trailing spaces should be ok
      assert length(code_edits) == 1
    end
  end

  # ──────────────────────────────────────────────────────────────
  # parse_code_and_tests/1
  # ──────────────────────────────────────────────────────────────

  describe "parse_code_and_tests/1" do
    test "parses both sections with full code" do
      response = """
      ---CODE---
      def handle(params) do
        Map.put(params, "ok", true)
      end
      ---TESTS---
      defmodule HandlerTest do
        use ExUnit.Case
        test "it works" do
          assert Handler.handle(%{}) == %{"ok" => true}
        end
      end
      """

      {code, tests} = FixPrompts.parse_code_and_tests(response)

      assert code =~ "def handle(params)"
      assert tests =~ "defmodule HandlerTest"
    end

    test "returns :error when CODE section missing" do
      response = """
      ---TESTS---
      test code here
      """

      assert :error = FixPrompts.parse_code_and_tests(response)
    end

    test "returns :error when TESTS section missing" do
      response = """
      ---CODE---
      handler code here
      """

      assert :error = FixPrompts.parse_code_and_tests(response)
    end

    test "returns :error for empty string" do
      assert :error = FixPrompts.parse_code_and_tests("")
    end

    test "returns :error for plain text" do
      assert :error = FixPrompts.parse_code_and_tests("just some text")
    end

    test "trims whitespace from both sections" do
      response = """
      ---CODE---

        def handle(p), do: p

      ---TESTS---

        test "x" do end

      """

      {code, tests} = FixPrompts.parse_code_and_tests(response)

      assert code == "def handle(p), do: p"
      assert tests == "test \"x\" do end"
    end

    test "handles code section with --- in content" do
      response = """
      ---CODE---
      @doc "Separator: ---"
      def handle(p), do: p
      ---TESTS---
      test "x" do end
      """

      {code, tests} = FixPrompts.parse_code_and_tests(response)

      # The @doc line with --- should be part of the code, not trigger TESTS section
      assert code =~ "Separator: ---"
      assert tests =~ "test"
    end

    test "handles empty CODE section" do
      response = """
      ---CODE---
      ---TESTS---
      test code
      """

      {code, tests} = FixPrompts.parse_code_and_tests(response)

      assert code == ""
      assert tests =~ "test code"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # build_context_section/1 (tested indirectly)
  # ──────────────────────────────────────────────────────────────

  describe "context section behavior" do
    test "all fix functions include context when log is non-empty" do
      context = "Attempt 1: changed foo to bar\nAttempt 2: added @spec"

      {_sys1, prompt1} = FixPrompts.fix_compilation("code", "error", context)
      {_sys2, prompt2} = FixPrompts.fix_lint("code", "issue", context)
      {_sys3, prompt3} = FixPrompts.fix_tests("code", "tests", "failure", context)

      for prompt <- [prompt1, prompt2, prompt3] do
        assert prompt =~ "Pipeline History"
        assert prompt =~ "do NOT repeat previous mistakes"
        assert prompt =~ "Attempt 1: changed foo to bar"
        assert prompt =~ "Attempt 2: added @spec"
      end
    end

    test "all fix functions omit context when log is empty" do
      {_sys1, prompt1} = FixPrompts.fix_compilation("code", "error", "")
      {_sys2, prompt2} = FixPrompts.fix_lint("code", "issue", "")
      {_sys3, prompt3} = FixPrompts.fix_tests("code", "tests", "failure", "")

      for prompt <- [prompt1, prompt2, prompt3] do
        refute prompt =~ "Pipeline History"
      end
    end
  end
end
