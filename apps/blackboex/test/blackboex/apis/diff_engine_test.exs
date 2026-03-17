defmodule Blackboex.Apis.DiffEngineTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Apis.DiffEngine

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
  end
end
