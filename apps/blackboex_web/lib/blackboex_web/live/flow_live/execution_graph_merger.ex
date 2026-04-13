defmodule BlackboexWeb.FlowLive.ExecutionGraphMerger do
  @moduledoc """
  Merges a BlackboexFlow graph definition with execution results by inserting
  "exec_data" nodes on edges between executed nodes.

  The merged graph preserves the original topology and adds data nodes that
  carry execution output/error/status, allowing the JS side to simply render
  the graph with auto-layout — no merge logic needed in the browser.
  """

  @doc """
  Merges execution data into a flow definition.

  For each edge where the source node was executed and has output (or error),
  and the target node was also executed, inserts an `exec_data` node on that edge.

  Returns a new definition with added nodes and rewired edges.
  """
  @spec merge(map(), list(map())) :: map()
  def merge(definition, []), do: definition

  def merge(definition, executions) do
    nodes = definition["nodes"]
    edges = definition["edges"] || []

    # Build a lookup of executed node data by ID
    exec_map = Map.new(executions, fn ex -> {ex.id, ex} end)
    executed_ids = MapSet.new(Map.keys(exec_map))

    # Find the max numeric ID to generate unique data node IDs
    max_num =
      nodes
      |> Enum.map(fn n -> n["id"] |> String.replace_leading("n", "") |> String.to_integer() end)
      |> Enum.max(fn -> 0 end)

    next_id_start = max(max_num + 1, 10_000)

    # Collect edges that need a data node inserted:
    # source was executed AND has output or error, AND target was executed
    edges_to_split =
      Enum.filter(edges, fn e ->
        source_id = e["source"]
        target_id = e["target"]

        MapSet.member?(executed_ids, source_id) and
          MapSet.member?(executed_ids, target_id) and
          has_output_or_error?(exec_map[source_id])
      end)

    # Generate data nodes and replacement edges
    {new_nodes, new_edges, _next_id} =
      Enum.reduce(edges_to_split, {[], [], next_id_start}, fn edge, {acc_nodes, acc_edges, next_id} ->
        source_exec = exec_map[edge["source"]]
        data_node_id = "n#{next_id}"

        data_node = %{
          "id" => data_node_id,
          "type" => "exec_data",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{
            "output" => source_exec.output,
            "error" => source_exec.error,
            "status" => source_exec.status,
            "duration_ms" => source_exec.duration_ms,
            "source_node" => edge["source"]
          }
        }

        # Split original edge into two: source → data_node, data_node → target
        edge_in = %{
          "id" => "e_#{edge["source"]}_#{edge["source_port"]}_#{data_node_id}_0",
          "source" => edge["source"],
          "source_port" => edge["source_port"],
          "target" => data_node_id,
          "target_port" => 0
        }

        edge_out = %{
          "id" => "e_#{data_node_id}_0_#{edge["target"]}_#{edge["target_port"]}",
          "source" => data_node_id,
          "source_port" => 0,
          "target" => edge["target"],
          "target_port" => edge["target_port"]
        }

        {[data_node | acc_nodes], [edge_in, edge_out | acc_edges], next_id + 1}
      end)

    # Remove split edges from original, keep unsplit ones
    split_edge_ids = MapSet.new(edges_to_split, & &1["id"])
    kept_edges = Enum.reject(edges, fn e -> MapSet.member?(split_edge_ids, e["id"]) end)

    %{
      "version" => definition["version"],
      "nodes" => nodes ++ Enum.reverse(new_nodes),
      "edges" => kept_edges ++ Enum.reverse(new_edges)
    }
  end

  defp has_output_or_error?(exec) do
    exec.output != nil or exec.error != nil
  end
end
