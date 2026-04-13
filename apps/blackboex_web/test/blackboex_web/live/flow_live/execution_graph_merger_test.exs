defmodule BlackboexWeb.FlowLive.ExecutionGraphMergerTest do
  use ExUnit.Case, async: true

  alias BlackboexWeb.FlowLive.ExecutionGraphMerger

  # Helper to build a minimal BlackboexFlow definition
  defp build_definition(nodes, edges) do
    %{
      "version" => "1.0",
      "nodes" => nodes,
      "edges" => edges
    }
  end

  defp node(id, type, x \\ 0, y \\ 0) do
    %{"id" => id, "type" => type, "position" => %{"x" => x, "y" => y}, "data" => %{}}
  end

  defp edge(source, target, source_port \\ 0, target_port \\ 0) do
    %{
      "id" => "e_#{source}_#{source_port}_#{target}_#{target_port}",
      "source" => source,
      "source_port" => source_port,
      "target" => target,
      "target_port" => target_port
    }
  end

  defp exec_node(node_id, status, output, opts \\ []) do
    %{
      id: node_id,
      status: status,
      duration_ms: Keyword.get(opts, :duration_ms, 100),
      input: Keyword.get(opts, :input),
      output: output,
      error: Keyword.get(opts, :error)
    }
  end

  describe "merge/2 with a linear flow (A → B → C)" do
    setup do
      definition =
        build_definition(
          [node("n1", "start"), node("n2", "http_request"), node("n3", "end")],
          [edge("n1", "n2"), edge("n2", "n3")]
        )

      executions = [
        exec_node("n1", "completed", %{"result" => "a"}),
        exec_node("n2", "completed", %{"result" => "b"}),
        exec_node("n3", "completed", %{"result" => "c"})
      ]

      %{definition: definition, executions: executions}
    end

    test "inserts data nodes between each pair of connected executed nodes",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      original_ids = MapSet.new(["n1", "n2", "n3"])
      all_ids = MapSet.new(Enum.map(merged["nodes"], & &1["id"]))
      data_node_ids = MapSet.difference(all_ids, original_ids)

      # A→B and B→C = 2 data nodes inserted
      assert MapSet.size(data_node_ids) == 2
    end

    test "data nodes have type exec_data and carry execution output",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      data_nodes =
        Enum.filter(merged["nodes"], fn n -> n["type"] == "exec_data" end)

      assert length(data_nodes) == 2

      Enum.each(data_nodes, fn dn ->
        assert is_map(dn["data"]["output"])
        assert dn["data"]["status"] in ["completed"]
      end)
    end

    test "edges are rewired through data nodes — no direct original→original edges remain",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      original_ids = MapSet.new(["n1", "n2", "n3"])

      # No edge should have both source and target in original_ids
      Enum.each(merged["edges"], fn e ->
        both_original =
          MapSet.member?(original_ids, e["source"]) and
            MapSet.member?(original_ids, e["target"])

        refute both_original,
               "Edge #{e["source"]} → #{e["target"]} should go through a data node"
      end)
    end

    test "total edge count doubles (each original edge split into two)",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      # Original: 2 edges. After merge: 4 edges (each split into 2)
      assert length(merged["edges"]) == 4
    end

    test "preserves original node positions",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      original_nodes =
        Enum.filter(merged["nodes"], fn n -> n["id"] in ["n1", "n2", "n3"] end)

      Enum.each(original_nodes, fn n ->
        original = Enum.find(def_["nodes"], &(&1["id"] == n["id"]))
        assert n["position"] == original["position"]
      end)
    end
  end

  describe "merge/2 with branching flow (A → B, A → C)" do
    setup do
      definition =
        build_definition(
          [
            node("n1", "start", 0, 100),
            node("n2", "http_request", 200, 0),
            node("n3", "http_request", 200, 200)
          ],
          [edge("n1", "n2", 0, 0), edge("n1", "n3", 0, 0)]
        )

      executions = [
        exec_node("n1", "completed", %{"x" => 1}),
        exec_node("n2", "completed", %{"y" => 2}),
        exec_node("n3", "completed", %{"z" => 3})
      ]

      %{definition: definition, executions: executions}
    end

    test "inserts a data node on each branch",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      data_nodes = Enum.filter(merged["nodes"], fn n -> n["type"] == "exec_data" end)

      # A→B and A→C = 2 data nodes (both from A's output)
      assert length(data_nodes) == 2
    end

    test "each branch has its own data node with source output",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      data_nodes = Enum.filter(merged["nodes"], fn n -> n["type"] == "exec_data" end)

      # Both should carry n1's output since n1 is the source
      Enum.each(data_nodes, fn dn ->
        assert dn["data"]["output"] == %{"x" => 1}
      end)
    end
  end

  describe "merge/2 with partial execution (only some nodes executed)" do
    setup do
      definition =
        build_definition(
          [
            node("n1", "start"),
            node("n2", "http_request"),
            node("n3", "condition"),
            node("n4", "end"),
            node("n5", "end")
          ],
          [edge("n1", "n2"), edge("n2", "n3"), edge("n3", "n4", 0, 0), edge("n3", "n5", 1, 0)]
        )

      # Only n1 → n2 → n3 → n4 executed (n5 branch not taken)
      executions = [
        exec_node("n1", "completed", %{"a" => 1}),
        exec_node("n2", "completed", %{"b" => 2}),
        exec_node("n3", "completed", %{"c" => 3}),
        exec_node("n4", "completed", %{"d" => 4})
      ]

      %{definition: definition, executions: executions}
    end

    test "only inserts data nodes on edges between executed nodes",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      data_nodes = Enum.filter(merged["nodes"], fn n -> n["type"] == "exec_data" end)

      # n1→n2, n2→n3, n3→n4 = 3 data nodes. n3→n5 NOT included (n5 not executed)
      assert length(data_nodes) == 3
    end

    test "non-executed nodes are preserved as-is",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      n5 = Enum.find(merged["nodes"], fn n -> n["id"] == "n5" end)
      assert n5 != nil
      assert n5["type"] == "end"
    end

    test "edge to non-executed node is preserved unchanged",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      # The edge n3→n5 should still exist directly (not split)
      n3_to_n5 =
        Enum.find(merged["edges"], fn e ->
          e["source"] == "n3" and e["target"] == "n5"
        end)

      assert n3_to_n5 != nil
    end
  end

  describe "merge/2 with node that has no output (error node)" do
    setup do
      definition =
        build_definition(
          [node("n1", "start"), node("n2", "http_request"), node("n3", "end")],
          [edge("n1", "n2"), edge("n2", "n3")]
        )

      executions = [
        exec_node("n1", "completed", %{"ok" => true}),
        exec_node("n2", "failed", nil, error: "timeout"),
        exec_node("n3", "skipped", nil)
      ]

      %{definition: definition, executions: executions}
    end

    test "inserts data node for error (no output but has error)",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      data_nodes = Enum.filter(merged["nodes"], fn n -> n["type"] == "exec_data" end)

      # n1→n2: n1 has output → data node inserted
      # n2→n3: n2 has error → data node inserted
      assert length(data_nodes) == 2
    end

    test "error data node carries the error field",
         %{definition: def_, executions: execs} do
      merged = ExecutionGraphMerger.merge(def_, execs)

      error_dn =
        Enum.find(merged["nodes"], fn n ->
          n["type"] == "exec_data" and n["data"]["error"] != nil
        end)

      assert error_dn != nil
      assert error_dn["data"]["error"] == "timeout"
    end
  end

  describe "merge/2 edge cases" do
    test "empty executions returns definition unchanged" do
      definition =
        build_definition(
          [node("n1", "start"), node("n2", "end")],
          [edge("n1", "n2")]
        )

      merged = ExecutionGraphMerger.merge(definition, [])

      assert merged == definition
    end

    test "single executed node with no outgoing edges to other executed nodes" do
      definition =
        build_definition(
          [node("n1", "start"), node("n2", "end")],
          [edge("n1", "n2")]
        )

      executions = [exec_node("n1", "completed", %{"x" => 1})]

      merged = ExecutionGraphMerger.merge(definition, executions)

      data_nodes = Enum.filter(merged["nodes"], fn n -> n["type"] == "exec_data" end)
      # n2 not executed, so no data node on n1→n2
      assert length(data_nodes) == 0
    end

    test "preserves version field" do
      definition = build_definition([node("n1", "start")], [])
      merged = ExecutionGraphMerger.merge(definition, [])
      assert merged["version"] == "1.0"
    end
  end
end
