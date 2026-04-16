defmodule Blackboex.Playgrounds.CompleterTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Playgrounds.Completer

  describe "complete/1 module completions" do
    test "returns matching modules for partial module name" do
      results = Completer.complete("Enu")
      assert Enum.any?(results, &(&1.label == "Enum"))
    end

    test "returns multiple matching modules" do
      results = Completer.complete("Ma")
      labels = Enum.map(results, & &1.label)
      assert "Map" in labels
      assert "MapSet" in labels
    end

    test "returns empty for blocked module prefix" do
      results = Completer.complete("Sys")
      refute Enum.any?(results, &(&1.label == "System"))
    end

    test "returns empty for File module" do
      results = Completer.complete("Fil")
      refute Enum.any?(results, &(&1.label == "File"))
    end

    test "module results have type module" do
      [result | _] = Completer.complete("Enu")
      assert result.type == "module"
    end
  end

  describe "complete/1 function completions" do
    test "returns functions after dot for allowed module" do
      results = Completer.complete("Enum.")
      labels = Enum.map(results, & &1.label)
      assert "map/2" in labels
      assert "filter/2" in labels
      assert "reduce/3" in labels
    end

    test "filters functions by prefix after dot" do
      results = Completer.complete("String.up")
      labels = Enum.map(results, & &1.label)
      assert "upcase/1" in labels
      refute "downcase/1" in labels
    end

    test "returns empty for blocked module dot" do
      assert [] = Completer.complete("System.")
      assert [] = Completer.complete("File.")
      assert [] = Completer.complete("Code.")
    end

    test "returns functions for Kernel module" do
      results = Completer.complete("Kernel.")
      labels = Enum.map(results, & &1.label)
      assert "is_nil/1" in labels
    end

    test "function results have type function" do
      [result | _] = Completer.complete("Enum.")
      assert result.type == "function"
    end

    test "function results include module as detail" do
      [result | _] = Completer.complete("Enum.")
      assert result.detail == "Enum"
    end
  end

  describe "complete/1 edge cases" do
    test "returns empty for empty hint" do
      assert [] = Completer.complete("")
    end

    test "returns empty for nonsense input" do
      assert [] = Completer.complete("zzzzz")
    end

    test "each result has required keys" do
      [result | _] = Completer.complete("Enum.")
      assert Map.has_key?(result, :label)
      assert Map.has_key?(result, :type)
    end

    test "handles hint with only a dot" do
      assert [] = Completer.complete(".")
    end
  end
end
