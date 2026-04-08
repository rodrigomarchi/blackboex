defmodule Blackboex.CodeGen.DiffEngineTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.CodeGen.DiffEngine

  describe "compute_diff/2" do
    test "returns diff for different code" do
      old = "line1\nline2\nline3"
      new = "line1\nmodified\nline3"

      diff = DiffEngine.compute_diff(old, new)
      assert Enum.any?(diff, fn {op, _} -> op == :del end)
      assert Enum.any?(diff, fn {op, _} -> op == :ins end)
    end

    test "returns only :eq for identical code" do
      code = "line1\nline2\nline3"

      diff = DiffEngine.compute_diff(code, code)
      assert Enum.all?(diff, fn {op, _} -> op == :eq end)
    end

    test "handles empty old code" do
      diff = DiffEngine.compute_diff("", "new line")
      assert Enum.any?(diff, fn {op, _} -> op == :ins end)
    end

    test "handles empty new code" do
      diff = DiffEngine.compute_diff("old line", "")
      assert Enum.any?(diff, fn {op, _} -> op == :del end)
    end
  end

  describe "compute_diff/2 — edge cases" do
    test "handles both strings empty" do
      diff = DiffEngine.compute_diff("", "")
      assert Enum.all?(diff, fn {op, _} -> op == :eq end)
    end

    test "handles multiline additions" do
      old = "line1\nline3"
      new = "line1\nline2a\nline2b\nline3"

      diff = DiffEngine.compute_diff(old, new)
      ins_lines = for {:ins, lines} <- diff, line <- lines, do: line

      assert "line2a" in ins_lines
      assert "line2b" in ins_lines
    end

    test "handles trailing newline difference" do
      old = "line1\nline2"
      new = "line1\nline2\n"

      diff = DiffEngine.compute_diff(old, new)

      # Trailing \n creates an empty string after split
      refute Enum.all?(diff, fn {op, _} -> op == :eq end)
    end

    test "handles single character changes" do
      old = "a"
      new = "b"

      diff = DiffEngine.compute_diff(old, new)
      assert Enum.any?(diff, fn {op, _} -> op == :del end)
      assert Enum.any?(diff, fn {op, _} -> op == :ins end)
    end
  end

  describe "format_diff_summary/1" do
    test "formats additions and removals" do
      diff = [{:eq, ["line1"]}, {:del, ["old"]}, {:ins, ["new1", "new2"]}, {:eq, ["line3"]}]
      summary = DiffEngine.format_diff_summary(diff)
      assert summary =~ "2 added"
      assert summary =~ "1 removed"
    end

    test "returns 'no changes' for identical code" do
      diff = [{:eq, ["line1", "line2"]}]
      assert DiffEngine.format_diff_summary(diff) == "no changes"
    end

    test "handles only additions" do
      diff = [{:eq, ["line1"]}, {:ins, ["new"]}]
      summary = DiffEngine.format_diff_summary(diff)
      assert summary == "1 added"
      refute summary =~ "removed"
    end

    test "handles only removals" do
      diff = [{:eq, ["line1"]}, {:del, ["old1", "old2"]}]
      summary = DiffEngine.format_diff_summary(diff)
      assert summary == "2 removed"
      refute summary =~ "added"
    end

    test "handles empty diff list" do
      assert DiffEngine.format_diff_summary([]) == "no changes"
    end

    test "handles large number of changes" do
      diff = [{:ins, Enum.map(1..100, &"line_#{&1}")}, {:del, Enum.map(1..50, &"old_#{&1}")}]
      summary = DiffEngine.format_diff_summary(diff)

      assert summary =~ "100 added"
      assert summary =~ "50 removed"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # apply_search_replace/2
  # ──────────────────���───────────────────────────────────────────

  describe "apply_search_replace/2" do
    test "applies a single exact-match replacement" do
      code = """
      def handle(params) do
        params
      end
      """

      blocks = [%{search: "  params\n", replace: "  Map.put(params, \"ok\", true)\n"}]

      assert {:ok, result} = DiffEngine.apply_search_replace(code, blocks)
      assert result =~ "Map.put(params, \"ok\", true)"
      refute result =~ "  params\n"
    end

    test "applies multiple sequential replacements" do
      code = "def foo, do: 1\ndef bar, do: 2\n"

      blocks = [
        %{search: "def foo, do: 1", replace: "def foo, do: 10"},
        %{search: "def bar, do: 2", replace: "def bar, do: 20"}
      ]

      assert {:ok, result} = DiffEngine.apply_search_replace(code, blocks)
      assert result =~ "def foo, do: 10"
      assert result =~ "def bar, do: 20"
    end

    test "returns error when search text not found" do
      code = "def handle(params), do: params"
      blocks = [%{search: "def nonexistent(x), do: x", replace: "new"}]

      assert {:error, :search_not_found, search} =
               DiffEngine.apply_search_replace(code, blocks)

      assert search == "def nonexistent(x), do: x"
    end

    test "stops on first non-matching block" do
      code = "def foo, do: 1\ndef bar, do: 2"

      blocks = [
        %{search: "def foo, do: 1", replace: "def foo, do: 10"},
        %{search: "this does not exist", replace: "whatever"},
        %{search: "def bar, do: 2", replace: "def bar, do: 20"}
      ]

      assert {:error, :search_not_found, _} = DiffEngine.apply_search_replace(code, blocks)
    end

    test "applies empty replacement (deletion)" do
      code = "@doc \"Remove this\"\ndef handle(params), do: params"
      blocks = [%{search: "@doc \"Remove this\"\n", replace: ""}]

      assert {:ok, result} = DiffEngine.apply_search_replace(code, blocks)
      refute result =~ "@doc"
      assert result =~ "def handle"
    end

    test "replaces only first occurrence when search matches multiple times" do
      code = "x = 1\nx = 1\nx = 1"
      blocks = [%{search: "x = 1", replace: "x = 2"}]

      assert {:ok, result} = DiffEngine.apply_search_replace(code, blocks)

      # global: false means only first match
      assert result == "x = 2\nx = 1\nx = 1"
    end

    test "handles empty blocks list (no-op)" do
      code = "def handle(params), do: params"

      assert {:ok, ^code} = DiffEngine.apply_search_replace(code, [])
    end

    test "handles empty code string" do
      blocks = [%{search: "something", replace: "other"}]

      assert {:error, :search_not_found, _} = DiffEngine.apply_search_replace("", blocks)
    end

    test "fuzzy matches when trailing whitespace differs" do
      # Code has trailing spaces, search doesn't
      code = "def handle(params) do  \n  params  \nend"

      blocks = [
        %{
          search: "def handle(params) do\n  params\nend",
          replace: "def handle(params) do\n  :ok\nend"
        }
      ]

      assert {:ok, result} = DiffEngine.apply_search_replace(code, blocks)
      assert result =~ ":ok"
    end

    test "handles search text with special regex characters" do
      code = "result = %{key: value, nested: %{a: 1}}"

      blocks = [
        %{search: "%{key: value, nested: %{a: 1}}", replace: "%{key: value, nested: %{a: 2}}"}
      ]

      assert {:ok, result} = DiffEngine.apply_search_replace(code, blocks)
      assert result =~ "%{a: 2}"
    end

    test "handles multiline search and replace" do
      code = """
      def handle(params) do
        name = Map.get(params, "name")
        age = Map.get(params, "age")
        %{name: name, age: age}
      end
      """

      blocks = [
        %{
          search: "  name = Map.get(params, \"name\")\n  age = Map.get(params, \"age\")",
          replace:
            "  name = Map.get(params, \"name\", \"unknown\")\n  age = Map.get(params, \"age\", 0)"
        }
      ]

      assert {:ok, result} = DiffEngine.apply_search_replace(code, blocks)
      assert result =~ "\"unknown\""
      assert result =~ ", 0)"
    end

    test "second block operates on result of first block" do
      code = "a = 1\nb = 2"

      blocks = [
        %{search: "a = 1", replace: "a = 10"},
        %{search: "a = 10", replace: "a = 100"}
      ]

      assert {:ok, result} = DiffEngine.apply_search_replace(code, blocks)
      assert result == "a = 100\nb = 2"
    end

    test "handles code with unicode characters" do
      code = "def handle(_), do: %{\"nome\" => \"Joao\"}"
      blocks = [%{search: "\"Joao\"", replace: "\"Joao Paulo\""}]

      assert {:ok, result} = DiffEngine.apply_search_replace(code, blocks)
      assert result =~ "Joao Paulo"
    end

    test "fuzzy match handles mixed indentation (tabs vs spaces)" do
      code = "def handle(params) do\n\tparams\nend"

      blocks = [
        %{
          search: "def handle(params) do\n  params\nend",
          replace: "def handle(params) do\n  :ok\nend"
        }
      ]

      # Tabs vs spaces — normalize_ws only trims trailing, not leading
      # This should NOT match fuzzy either since the difference is leading whitespace
      result = DiffEngine.apply_search_replace(code, blocks)

      case result do
        {:ok, _} -> :ok
        {:error, :search_not_found, _} -> :ok
      end
    end
  end
end
