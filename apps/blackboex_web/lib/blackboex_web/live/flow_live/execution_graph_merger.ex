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
  @spec merge(map(), list(map()), map()) :: map()
  def merge(definition, executions, execution_io \\ %{})

  def merge(definition, [], _execution_io), do: definition

  def merge(definition, executions, execution_io) do
    nodes = definition["nodes"]
    edges = definition["edges"] || []

    # Build a lookup of executed node data by ID, excluding skipped nodes
    exec_map = Map.new(executions, fn ex -> {ex.id, ex} end)

    executed_ids =
      executions
      |> Enum.reject(&skipped?/1)
      |> MapSet.new(& &1.id)

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
      Enum.reduce(edges_to_split, {[], [], next_id_start}, fn edge,
                                                              {acc_nodes, acc_edges, next_id} ->
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

    all_nodes = nodes ++ Enum.reverse(new_nodes)
    all_edges = kept_edges ++ Enum.reverse(new_edges)

    # Add boundary data nodes for execution input (before start) and output (after end)
    {all_nodes, all_edges, _} =
      add_boundary_nodes(
        all_nodes,
        all_edges,
        nodes,
        executed_ids,
        execution_io,
        next_id_start + length(new_nodes)
      )

    %{
      "version" => definition["version"],
      "nodes" => all_nodes,
      "edges" => all_edges
    }
  end

  defp add_boundary_nodes(all_nodes, all_edges, orig_nodes, executed_ids, execution_io, next_id) do
    # Find executed start node → add input data node before it
    start_node =
      Enum.find(orig_nodes, fn n ->
        n["type"] == "start" and MapSet.member?(executed_ids, n["id"])
      end)

    # Find executed end nodes (non-skipped) → add output data node after the first one
    end_node =
      Enum.find(orig_nodes, fn n ->
        n["type"] == "end" and MapSet.member?(executed_ids, n["id"])
      end)

    {all_nodes, all_edges, next_id} =
      maybe_add_input_node(all_nodes, all_edges, start_node, execution_io, next_id)

    maybe_add_output_node(all_nodes, all_edges, end_node, execution_io, next_id)
  end

  defp maybe_add_input_node(nodes, edges, nil, _io, next_id), do: {nodes, edges, next_id}

  defp maybe_add_input_node(nodes, edges, _start, %{input: nil}, next_id),
    do: {nodes, edges, next_id}

  defp maybe_add_input_node(nodes, edges, start_node, %{input: input}, next_id) do
    data_id = "n#{next_id}"

    data_node = %{
      "id" => data_id,
      "type" => "exec_data",
      "position" => %{"x" => 0, "y" => 0},
      "data" => %{
        "output" => input,
        "error" => nil,
        "status" => "completed",
        "duration_ms" => nil,
        "source_node" => "input"
      }
    }

    edge = %{
      "id" => "e_#{data_id}_0_#{start_node["id"]}_0",
      "source" => data_id,
      "source_port" => 0,
      "target" => start_node["id"],
      "target_port" => 0
    }

    {nodes ++ [data_node], edges ++ [edge], next_id + 1}
  end

  defp maybe_add_input_node(nodes, edges, _start, _io, next_id), do: {nodes, edges, next_id}

  defp maybe_add_output_node(nodes, edges, nil, _io, next_id), do: {nodes, edges, next_id}

  defp maybe_add_output_node(nodes, edges, _end, %{output: nil}, next_id),
    do: {nodes, edges, next_id}

  defp maybe_add_output_node(nodes, edges, end_node, %{output: output}, next_id) do
    data_id = "n#{next_id}"

    data_node = %{
      "id" => data_id,
      "type" => "exec_data",
      "position" => %{"x" => 0, "y" => 0},
      "data" => %{
        "output" => output,
        "error" => nil,
        "status" => "completed",
        "duration_ms" => nil,
        "source_node" => "output"
      }
    }

    edge = %{
      "id" => "e_#{end_node["id"]}_0_#{data_id}_0",
      "source" => end_node["id"],
      "source_port" => 0,
      "target" => data_id,
      "target_port" => 0
    }

    {nodes ++ [data_node], edges ++ [edge], next_id + 1}
  end

  defp maybe_add_output_node(nodes, edges, _end, _io, next_id), do: {nodes, edges, next_id}

  defp has_output_or_error?(exec) do
    exec.output != nil or exec.error != nil
  end

  defp skipped?(%{status: "skipped"}), do: true
  defp skipped?(%{output: %{"output" => "__branch_skipped__"}}), do: true
  defp skipped?(_), do: false
end
