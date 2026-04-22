defmodule Blackboex.FlowAgent.AutoLayoutTest do
  use ExUnit.Case, async: true

  alias Blackboex.FlowAgent.AutoLayout

  defp node(id, type, opts \\ []) do
    base = %{"id" => id, "type" => type, "data" => %{}}

    case Keyword.get(opts, :pos) do
      nil -> base
      {x, y} -> Map.put(base, "position", %{"x" => x, "y" => y})
    end
  end

  defp edge(id, source, target, source_port \\ 0, target_port \\ 0) do
    %{
      "id" => id,
      "source" => source,
      "source_port" => source_port,
      "target" => target,
      "target_port" => target_port
    }
  end

  describe "apply/1" do
    test "leaves existing positions intact when all nodes have them" do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          node("n1", "start", pos: {50, 250}),
          node("n2", "end", pos: {250, 250})
        ],
        "edges" => [edge("e1", "n1", "n2")]
      }

      assert AutoLayout.apply(definition) == definition
    end

    test "assigns positions when all are missing" do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          node("n1", "start"),
          node("n2", "elixir_code"),
          node("n3", "end")
        ],
        "edges" => [edge("e1", "n1", "n2"), edge("e2", "n2", "n3")]
      }

      laid_out = AutoLayout.apply(definition)

      for n <- laid_out["nodes"] do
        assert %{"x" => x, "y" => y} = n["position"]
        assert is_integer(x)
        assert is_integer(y)
      end
    end

    test "orders nodes by topological depth on x axis (start x=50, +200 per level)" do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          node("n1", "start"),
          node("n2", "elixir_code"),
          node("n3", "end")
        ],
        "edges" => [edge("e1", "n1", "n2"), edge("e2", "n2", "n3")]
      }

      laid_out = AutoLayout.apply(definition)
      positions = for n <- laid_out["nodes"], into: %{}, do: {n["id"], n["position"]}

      assert %{"x" => 50} = positions["n1"]
      assert %{"x" => 250} = positions["n2"]
      assert %{"x" => 450} = positions["n3"]
    end

    test "spreads branches on y axis (+150 per sibling)" do
      # n1 → n2, n1 → n3 — n2 and n3 at same depth, different y
      definition = %{
        "version" => "1.0",
        "nodes" => [
          node("n1", "condition"),
          node("n2", "end"),
          node("n3", "end")
        ],
        "edges" => [edge("e1", "n1", "n2", 0), edge("e2", "n1", "n3", 1)]
      }

      laid_out = AutoLayout.apply(definition)
      positions = for n <- laid_out["nodes"], into: %{}, do: {n["id"], n["position"]}

      assert positions["n2"]["x"] == positions["n3"]["x"]
      assert positions["n2"]["y"] != positions["n3"]["y"]
    end

    test "preserves partial positions (only fills missing ones)" do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          node("n1", "start", pos: {10, 20}),
          node("n2", "end")
        ],
        "edges" => [edge("e1", "n1", "n2")]
      }

      laid_out = AutoLayout.apply(definition)
      positions = for n <- laid_out["nodes"], into: %{}, do: {n["id"], n["position"]}

      assert positions["n1"] == %{"x" => 10, "y" => 20}
      assert is_integer(positions["n2"]["x"])
    end

    test "handles disconnected subgraphs by placing orphans below main flow" do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          node("n1", "start"),
          node("n2", "end"),
          node("n3", "elixir_code"),
          node("n4", "end")
        ],
        "edges" => [edge("e1", "n1", "n2"), edge("e2", "n3", "n4")]
      }

      laid_out = AutoLayout.apply(definition)
      positions = for n <- laid_out["nodes"], into: %{}, do: {n["id"], n["position"]}

      # Orphan subgraph (n3→n4) lands below the main one
      assert positions["n3"]["y"] > positions["n1"]["y"]
    end

    test "returns unchanged definition when nodes list empty" do
      empty = %{"version" => "1.0", "nodes" => [], "edges" => []}
      assert AutoLayout.apply(empty) == empty
    end

    test "preserves nodes/edges structure (only mutates position)" do
      definition = %{
        "version" => "1.0",
        "nodes" => [node("n1", "start"), node("n2", "end")],
        "edges" => [edge("e1", "n1", "n2")]
      }

      laid_out = AutoLayout.apply(definition)

      assert laid_out["version"] == "1.0"
      assert length(laid_out["nodes"]) == 2
      assert laid_out["edges"] == definition["edges"]

      # Non-position keys untouched
      for n <- laid_out["nodes"] do
        assert n["type"]
        assert n["data"] == %{}
      end
    end

    test "is deterministic (same input → same output)" do
      definition = %{
        "version" => "1.0",
        "nodes" => [node("n1", "start"), node("n2", "elixir_code"), node("n3", "end")],
        "edges" => [edge("e1", "n1", "n2"), edge("e2", "n2", "n3")]
      }

      assert AutoLayout.apply(definition) == AutoLayout.apply(definition)
    end

    test "terminates and assigns positions when graph has cycles" do
      # Pathological: n1 → n2 → n1. The BFS visited set prevents infinite loops.
      # BlackboexFlow.validate rejects cycles upstream, but AutoLayout is a
      # public module and must not hang if called with cyclic input.
      definition = %{
        "version" => "1.0",
        "nodes" => [node("n1", "elixir_code"), node("n2", "elixir_code")],
        "edges" => [edge("e1", "n1", "n2"), edge("e2", "n2", "n1")]
      }

      laid_out = AutoLayout.apply(definition)

      positions = for n <- laid_out["nodes"], into: %{}, do: {n["id"], n["position"]}
      assert is_integer(positions["n1"]["x"])
      assert is_integer(positions["n2"]["x"])
    end

    test "works when start node missing (uses arbitrary root)" do
      definition = %{
        "version" => "1.0",
        "nodes" => [node("n1", "elixir_code"), node("n2", "end")],
        "edges" => [edge("e1", "n1", "n2")]
      }

      laid_out = AutoLayout.apply(definition)
      positions = for n <- laid_out["nodes"], into: %{}, do: {n["id"], n["position"]}
      assert positions["n1"]["x"] < positions["n2"]["x"]
    end
  end
end
