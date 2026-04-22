defmodule Blackboex.FlowAgent.AutoLayout do
  @moduledoc """
  Assigns `position` coordinates to flow nodes that don't already have them.

  Runs a BFS from the start node (or any root — node with no incoming edges),
  places nodes at `x = 50 + depth * 200` per topological depth, and spreads
  siblings vertically around a center line. Disconnected subgraphs are
  stacked vertically below the main component, each separated by a gap.

  Nodes that already have an integer `position.x`/`position.y` are left
  untouched; this keeps the layout idempotent and respects LLM-supplied
  positions when they exist.
  """

  @base_x 50
  @base_y 250
  @col_width 200
  @row_height 150
  @component_gap 200

  @spec apply(map()) :: map()
  def apply(%{"nodes" => []} = definition), do: definition

  def apply(%{"nodes" => nodes, "edges" => edges} = definition)
      when is_list(nodes) and is_list(edges) do
    if Enum.all?(nodes, &has_position?/1) do
      definition
    else
      computed = compute_positions(nodes, edges)
      new_nodes = Enum.map(nodes, &merge_position(&1, computed))
      Map.put(definition, "nodes", new_nodes)
    end
  end

  def apply(definition), do: definition

  defp merge_position(node, computed) do
    if has_position?(node) do
      node
    else
      merge_computed_position(node, computed)
    end
  end

  defp merge_computed_position(node, computed) do
    case computed[node["id"]] do
      nil -> node
      pos -> Map.put(node, "position", pos)
    end
  end

  defp has_position?(%{"position" => %{"x" => x, "y" => y}})
       when is_integer(x) and is_integer(y),
       do: true

  defp has_position?(_), do: false

  defp compute_positions(nodes, edges) do
    children_of = build_children(edges)
    parents_of = build_parents(edges)
    ordered_roots = roots(nodes, parents_of)

    # Each root seeds a component; iterate so orphan components stack.
    {components, _visited} =
      Enum.reduce(ordered_roots ++ unreachable_seeds(nodes, parents_of), {[], MapSet.new()}, fn
        seed_id, {comps, visited} ->
          if MapSet.member?(visited, seed_id) do
            {comps, visited}
          else
            {layers, visited} = bfs(seed_id, children_of, visited)
            {comps ++ [layers], visited}
          end
      end)

    layout_components(components)
  end

  defp build_children(edges) do
    edges
    |> Enum.sort_by(&{&1["source"] || "", &1["source_port"] || 0})
    |> Enum.reduce(%{}, fn e, acc ->
      Map.update(acc, e["source"], [e["target"]], fn list -> list ++ [e["target"]] end)
    end)
  end

  defp build_parents(edges) do
    Enum.reduce(edges, %{}, fn e, acc ->
      Map.update(acc, e["target"], [e["source"]], fn list -> [e["source"] | list] end)
    end)
  end

  defp roots(nodes, parents_of) do
    candidates = Enum.filter(nodes, fn n -> Map.get(parents_of, n["id"], []) == [] end)
    {starts, others} = Enum.split_with(candidates, &(&1["type"] == "start"))
    Enum.map(starts ++ others, & &1["id"])
  end

  # For pathological cases (cycles, nodes with no roots in their component),
  # fall back to seeding BFS from every remaining node in document order.
  defp unreachable_seeds(nodes, parents_of) do
    for n <- nodes, Map.get(parents_of, n["id"], []) != [], do: n["id"]
  end

  defp bfs(seed_id, children_of, visited) do
    do_bfs([{seed_id, 0}], children_of, visited, %{})
  end

  defp do_bfs([], _children_of, visited, layers), do: {layers, visited}

  defp do_bfs([{id, depth} | rest], children_of, visited, layers) do
    if MapSet.member?(visited, id) do
      do_bfs(rest, children_of, visited, layers)
    else
      visited = MapSet.put(visited, id)
      layers = Map.update(layers, depth, [id], fn ids -> ids ++ [id] end)
      children = Map.get(children_of, id, [])
      next = rest ++ Enum.map(children, fn c -> {c, depth + 1} end)
      do_bfs(next, children_of, visited, layers)
    end
  end

  defp layout_components(components) do
    {_, positions} =
      Enum.reduce(components, {@base_y, %{}}, fn layers, {y_top, acc} ->
        max_per_layer =
          layers
          |> Map.values()
          |> Enum.map(&length/1)
          |> Enum.max(fn -> 1 end)

        component_height = max_per_layer * @row_height
        center_y = y_top + div(component_height, 2)

        component_positions =
          for {depth, ids} <- layers, {id, i} <- Enum.with_index(ids), into: %{} do
            n = length(ids)
            offset = round((i - (n - 1) / 2) * @row_height)
            {id, %{"x" => @base_x + depth * @col_width, "y" => center_y + offset}}
          end

        {y_top + component_height + @component_gap, Map.merge(acc, component_positions)}
      end)

    positions
  end
end
