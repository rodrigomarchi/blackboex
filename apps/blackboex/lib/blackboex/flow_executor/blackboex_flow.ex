defmodule Blackboex.FlowExecutor.BlackboexFlow do
  @moduledoc """
  Validates the canonical BlackboexFlow JSON format.

  BlackboexFlow is the single source of truth for flow definitions.
  The Drawflow editor converts to/from this format at the JS boundary.
  The server only ever sees BlackboexFlow JSON.

  ## Format

      %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 100, "y" => 200}, "data" => %{...}},
          ...
        ],
        "edges" => [
          %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
          ...
        ]
      }
  """

  @current_version "1.0"
  @valid_node_types ~w(start elixir_code condition end)

  @spec current_version() :: String.t()
  def current_version, do: @current_version

  @spec validate(map()) :: :ok | {:error, String.t()}
  def validate(%{"version" => version} = definition) when is_binary(version) do
    with :ok <- validate_version(version),
         :ok <- validate_nodes(definition),
         :ok <- validate_edges(definition),
         :ok <- validate_edge_refs(definition) do
      :ok
    end
  end

  def validate(%{}), do: {:error, "missing required field: version"}
  def validate(_), do: {:error, "definition must be a map"}

  # ── Private ──────────────────────────────────────────────────

  defp validate_version(@current_version), do: :ok
  defp validate_version(v), do: {:error, "unsupported version: #{v}"}

  defp validate_nodes(%{"nodes" => nodes}) when is_list(nodes) do
    case validate_each_node(nodes, []) do
      :ok -> validate_node_ids_unique(nodes)
      error -> error
    end
  end

  defp validate_nodes(_), do: {:error, "missing or invalid field: nodes"}

  defp validate_each_node([], _seen), do: :ok

  defp validate_each_node([node | rest], seen) do
    with :ok <- validate_node_shape(node),
         :ok <- validate_node_type(node) do
      validate_each_node(rest, [node["id"] | seen])
    end
  end

  defp validate_node_shape(%{"id" => id, "type" => type, "position" => pos, "data" => _data})
       when is_binary(id) and is_binary(type) and is_map(pos) do
    case pos do
      %{"x" => x, "y" => y} when is_number(x) and is_number(y) -> :ok
      _ -> {:error, "node #{id}: position must have numeric x and y"}
    end
  end

  defp validate_node_shape(%{"id" => id}) do
    {:error, "node #{id}: missing required fields (type, position, data)"}
  end

  defp validate_node_shape(_), do: {:error, "node missing required field: id"}

  defp validate_node_type(%{"id" => id, "type" => type}) do
    if type in @valid_node_types do
      :ok
    else
      {:error,
       "node #{id}: invalid type '#{type}', expected one of: #{Enum.join(@valid_node_types, ", ")}"}
    end
  end

  defp validate_node_ids_unique(nodes) do
    ids = Enum.map(nodes, & &1["id"])

    case ids -- Enum.uniq(ids) do
      [] -> :ok
      dupes -> {:error, "duplicate node ids: #{Enum.join(Enum.uniq(dupes), ", ")}"}
    end
  end

  defp validate_edges(%{"edges" => edges}) when is_list(edges) do
    validate_each_edge(edges)
  end

  defp validate_edges(%{"edges" => _}), do: {:error, "edges must be a list"}
  defp validate_edges(_), do: {:error, "missing required field: edges"}

  defp validate_each_edge([]), do: :ok

  defp validate_each_edge([edge | rest]) do
    case validate_edge_shape(edge) do
      :ok -> validate_each_edge(rest)
      error -> error
    end
  end

  defp validate_edge_shape(%{
         "id" => id,
         "source" => s,
         "source_port" => sp,
         "target" => t,
         "target_port" => tp
       })
       when is_binary(id) and is_binary(s) and is_integer(sp) and is_binary(t) and
              is_integer(tp) do
    :ok
  end

  defp validate_edge_shape(%{"id" => id}) do
    {:error, "edge #{id}: missing or invalid fields (source, source_port, target, target_port)"}
  end

  defp validate_edge_shape(_), do: {:error, "edge missing required field: id"}

  defp validate_edge_refs(%{"nodes" => nodes, "edges" => edges}) do
    node_ids = MapSet.new(nodes, & &1["id"])

    Enum.reduce_while(edges, :ok, fn edge, :ok ->
      cond do
        edge["source"] not in node_ids ->
          {:halt,
           {:error, "edge #{edge["id"]}: source '#{edge["source"]}' references non-existent node"}}

        edge["target"] not in node_ids ->
          {:halt,
           {:error, "edge #{edge["id"]}: target '#{edge["target"]}' references non-existent node"}}

        true ->
          {:cont, :ok}
      end
    end)
  end
end
