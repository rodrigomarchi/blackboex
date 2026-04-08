defmodule Blackboex.FlowExecutor.DefinitionParser do
  @moduledoc """
  Parses a BlackboexFlow JSON map into a `%ParsedFlow{}` struct with
  structural validations (single start, DAG, reachability).
  """

  alias Blackboex.FlowExecutor.{ParsedFlow, ParsedNode}

  @known_types ~w(start elixir_code condition end)a

  @spec parse(map()) :: {:ok, ParsedFlow.t()} | {:error, term()}
  def parse(definition) when is_map(definition) do
    with {:ok, nodes} <- parse_nodes(definition),
         {:ok, edges} <- parse_edges(definition),
         {:ok, start_node} <- find_start_node(nodes),
         {:ok, end_node_ids} <- find_end_nodes(nodes),
         adjacency <- build_adjacency(edges),
         :ok <- validate_no_cycles(adjacency, nodes),
         :ok <- validate_no_orphans(adjacency, start_node, nodes) do
      {:ok,
       %ParsedFlow{
         nodes: nodes,
         edges: edges,
         start_node: start_node,
         end_node_ids: end_node_ids,
         adjacency: adjacency
       }}
    end
  end

  # ── Nodes ──────────────────────────────────────────────────────

  @spec parse_nodes(map()) :: {:ok, [ParsedNode.t()]} | {:error, term()}
  defp parse_nodes(%{"nodes" => nodes}) when is_list(nodes) do
    Enum.reduce_while(nodes, {:ok, []}, fn raw_node, {:ok, acc} ->
      case to_parsed_node(raw_node) do
        {:ok, node} -> {:cont, {:ok, [node | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp parse_nodes(_), do: {:error, :invalid_definition}

  defp to_parsed_node(%{"id" => id, "type" => type, "position" => pos, "data" => data}) do
    case safe_to_atom(type) do
      {:error, _} = err ->
        err

      atom_type ->
        {:ok,
         %ParsedNode{
           id: id,
           type: atom_type,
           position: %{x: pos["x"], y: pos["y"]},
           data: data
         }}
    end
  end

  @known_type_strings Enum.map(@known_types, &Atom.to_string/1)

  defp safe_to_atom(type) when type in @known_type_strings do
    String.to_existing_atom(type)
  end

  defp safe_to_atom(type) when is_binary(type) do
    {:error, {:unknown_node_type, type}}
  end

  # ── Edges ──────────────────────────────────────────────────────

  @spec parse_edges(map()) :: {:ok, [ParsedFlow.edge()]} | {:error, term()}
  defp parse_edges(%{"edges" => edges}) when is_list(edges) do
    {:ok, Enum.map(edges, &to_edge/1)}
  end

  defp parse_edges(_), do: {:error, :invalid_definition}

  defp to_edge(%{
         "id" => id,
         "source" => s,
         "source_port" => sp,
         "target" => t,
         "target_port" => tp
       }) do
    %{id: id, source: s, source_port: sp, target: t, target_port: tp}
  end

  # ── Structural Validations ────────────────────────────────────

  @spec find_start_node([ParsedNode.t()]) :: {:ok, ParsedNode.t()} | {:error, term()}
  defp find_start_node(nodes) do
    case Enum.filter(nodes, &(&1.type == :start)) do
      [start] -> {:ok, start}
      [] -> {:error, :no_start_node}
      _many -> {:error, :multiple_start_nodes}
    end
  end

  @spec find_end_nodes([ParsedNode.t()]) :: {:ok, [String.t()]} | {:error, term()}
  defp find_end_nodes(nodes) do
    case Enum.filter(nodes, &(&1.type == :end)) |> Enum.map(& &1.id) do
      [] -> {:error, :no_end_node}
      ids -> {:ok, ids}
    end
  end

  @spec build_adjacency([ParsedFlow.edge()]) :: %{String.t() => [String.t()]}
  defp build_adjacency(edges) do
    Enum.reduce(edges, %{}, fn edge, acc ->
      Map.update(acc, edge.source, [edge.target], &[edge.target | &1])
    end)
  end

  @spec validate_no_cycles(%{String.t() => [String.t()]}, [ParsedNode.t()]) ::
          :ok | {:error, {:cycle_detected, String.t()}}
  defp validate_no_cycles(adjacency, nodes) do
    node_ids = Enum.map(nodes, & &1.id)

    result =
      Enum.reduce_while(node_ids, MapSet.new(), fn node_id, visited ->
        visit_node(node_id, adjacency, visited)
      end)

    case result do
      {:error, _} = err -> err
      _visited -> :ok
    end
  end

  defp visit_node(node_id, adjacency, visited) do
    if MapSet.member?(visited, node_id) do
      {:cont, visited}
    else
      case dfs_cycle(node_id, adjacency, MapSet.new(), visited) do
        {:ok, new_visited} -> {:cont, new_visited}
        {:error, _} = err -> {:halt, err}
      end
    end
  end

  defp dfs_cycle(node_id, adjacency, path, visited) do
    cond do
      MapSet.member?(path, node_id) ->
        {:error, {:cycle_detected, node_id}}

      MapSet.member?(visited, node_id) ->
        {:ok, visited}

      true ->
        dfs_cycle_neighbors(node_id, adjacency, MapSet.put(path, node_id), visited)
    end
  end

  defp dfs_cycle_neighbors(node_id, adjacency, path, visited) do
    neighbors = Map.get(adjacency, node_id, [])

    result =
      Enum.reduce_while(neighbors, {:ok, visited}, fn neighbor, {:ok, acc} ->
        case dfs_cycle(neighbor, adjacency, path, acc) do
          {:ok, new_visited} -> {:cont, {:ok, new_visited}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case result do
      {:ok, final_visited} -> {:ok, MapSet.put(final_visited, node_id)}
      {:error, _} = err -> err
    end
  end

  @spec validate_no_orphans(%{String.t() => [String.t()]}, ParsedNode.t(), [ParsedNode.t()]) ::
          :ok | {:error, {:orphan_nodes, [String.t()]}}
  defp validate_no_orphans(adjacency, start_node, nodes) do
    reachable = bfs_reachable(adjacency, start_node.id)
    all_ids = MapSet.new(nodes, & &1.id)
    orphans = MapSet.difference(all_ids, reachable) |> MapSet.to_list() |> Enum.sort()

    case orphans do
      [] -> :ok
      ids -> {:error, {:orphan_nodes, ids}}
    end
  end

  defp bfs_reachable(adjacency, start_id) do
    bfs_reachable([start_id], adjacency, MapSet.new())
  end

  defp bfs_reachable([], _adjacency, visited), do: visited

  defp bfs_reachable([current | rest], adjacency, visited) do
    if MapSet.member?(visited, current) do
      bfs_reachable(rest, adjacency, visited)
    else
      visited = MapSet.put(visited, current)
      neighbors = Map.get(adjacency, current, [])
      bfs_reachable(rest ++ neighbors, adjacency, visited)
    end
  end
end
