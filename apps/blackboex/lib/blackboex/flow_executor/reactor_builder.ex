defmodule Blackboex.FlowExecutor.ReactorBuilder do
  @moduledoc """
  Builds a Reactor from a ParsedFlow.

  Converts the parsed flow definition into a Reactor with steps wired together
  via arguments. Each node becomes a Reactor step with the appropriate
  implementation module.

  ## Branch Gating

  Condition nodes output `%{branch: index, value: input, state: state}`.
  Downstream nodes of a condition are wrapped in a `BranchGate` step that
  checks whether the branch index matches the edge's source_port. If it
  doesn't match, the gate passes `nil` — the downstream step is skipped.
  """

  alias Blackboex.FlowExecutor.{ExecutionMiddleware, ParsedFlow, ParsedNode}

  alias Blackboex.FlowExecutor.Nodes.{
    Condition,
    ElixirCode,
    EndNode,
    Start
  }

  alias Reactor.{Argument, Builder}

  @max_nodes 100
  @max_edges 500

  @spec build(ParsedFlow.t()) :: {:ok, Reactor.t()} | {:error, any()}
  def build(%ParsedFlow{} = parsed_flow) do
    with :ok <- validate_limits(parsed_flow) do
      reactor = Builder.new()

      with {:ok, reactor} <- Builder.add_input(reactor, :payload),
           {:ok, reactor} <- add_all_steps(reactor, parsed_flow),
           {:ok, reactor} <- set_return(reactor, parsed_flow),
           {:ok, reactor} <- Builder.add_middleware(reactor, ExecutionMiddleware) do
        {:ok, reactor}
      end
    end
  end

  # ── Private ──────────────────────────────────────────────────

  defp validate_limits(%ParsedFlow{nodes: nodes, edges: edges}) do
    cond do
      length(nodes) > @max_nodes ->
        {:error, "flow exceeds maximum of #{@max_nodes} nodes"}

      length(edges) > @max_edges ->
        {:error, "flow exceeds maximum of #{@max_edges} edges"}

      true ->
        :ok
    end
  end

  defp add_all_steps(reactor, %ParsedFlow{} = parsed_flow) do
    ordered = topological_sort(parsed_flow)

    Enum.reduce_while(ordered, {:ok, reactor}, fn node, {:ok, reactor} ->
      case add_node_step(reactor, node, parsed_flow) do
        {:ok, reactor} -> {:cont, {:ok, reactor}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp add_node_step(reactor, %ParsedNode{type: :start} = node, _parsed_flow) do
    Builder.add_step(
      reactor,
      step_name(node.id),
      Start,
      [Argument.from_input(:payload, :payload)],
      async?: false
    )
  end

  defp add_node_step(reactor, %ParsedNode{type: :elixir_code} = node, parsed_flow) do
    code = node.data["code"] || ""
    timeout_ms = parse_timeout(node.data["timeout_ms"], 5_000)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {ElixirCode, code: code, timeout_ms: timeout_ms},
      [build_input_argument(node, parsed_flow)],
      async?: false
    )
  end

  defp add_node_step(reactor, %ParsedNode{type: :condition} = node, parsed_flow) do
    expression = node.data["expression"] || "0"
    timeout_ms = parse_timeout(node.data["timeout_ms"], 5_000)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {Condition, expression: expression, timeout_ms: timeout_ms},
      [build_input_argument(node, parsed_flow)],
      async?: false
    )
  end

  defp add_node_step(reactor, %ParsedNode{type: :end} = node, parsed_flow) do
    Builder.add_step(
      reactor,
      step_name(node.id),
      EndNode,
      [build_input_argument(node, parsed_flow)],
      async?: false
    )
  end

  defp build_input_argument(%ParsedNode{} = node, %ParsedFlow{} = parsed_flow) do
    incoming =
      Enum.filter(parsed_flow.edges, fn edge ->
        edge.target == node.id
      end)

    case incoming do
      [] ->
        Argument.from_input(:prev_result, :payload)

      [edge | _] ->
        source_step = step_name(edge.source)
        source_node = Enum.find(parsed_flow.nodes, &(&1.id == edge.source))

        if source_node && source_node.type == :condition do
          # Apply branch gating: transform filters by the edge's source_port
          expected_branch = edge.source_port

          Argument.from_result(:prev_result, source_step,
            transform: &branch_gate(&1, expected_branch)
          )
        else
          Argument.from_result(:prev_result, source_step)
        end
    end
  end

  defp branch_gate(%{branch: branch, value: value, state: state}, expected_branch) do
    if branch == expected_branch do
      %{output: value, state: state}
    else
      %{output: :__branch_skipped__, state: state}
    end
  end

  defp branch_gate(other, _expected_branch), do: other

  defp set_return(reactor, %ParsedFlow{end_node_ids: [end_id]}) do
    Builder.return(reactor, step_name(end_id))
  end

  defp set_return(reactor, %ParsedFlow{end_node_ids: end_ids}) when length(end_ids) > 1 do
    # Multiple end nodes (branching flows): add a collector step that picks
    # the first non-skipped result. Each end node feeds into the collector.
    args =
      Enum.map(end_ids, fn id ->
        Argument.from_result(String.to_atom("end_#{id}"), step_name(id))
      end)

    with {:ok, reactor} <-
           Builder.add_step(reactor, :__flow_collector__, {__MODULE__.Collector, []}, args,
             async?: false
           ) do
      Builder.return(reactor, :__flow_collector__)
    end
  end

  defp set_return(_reactor, _parsed_flow) do
    {:error, "no end node found to set as return"}
  end

  # Use a bounded set of atom names — node IDs are validated to match /^n\d+$/
  # and capped at @max_nodes, so atom table growth is bounded.
  defp step_name(node_id) when is_binary(node_id) do
    String.to_atom("node_#{node_id}")
  end

  defp parse_timeout(val, _default) when is_integer(val) and val > 0, do: val
  defp parse_timeout(val, default) when is_binary(val), do: parse_timeout(to_int(val), default)
  defp parse_timeout(_val, default), do: default

  defp to_int(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp topological_sort(%ParsedFlow{nodes: nodes, adjacency: adjacency}) do
    node_ids = Enum.map(nodes, & &1.id)
    node_map = Map.new(nodes, &{&1.id, &1})

    in_degree =
      Enum.reduce(node_ids, %{}, fn id, acc ->
        Map.put(acc, id, 0)
      end)

    in_degree =
      Enum.reduce(adjacency, in_degree, fn {_src, targets}, acc ->
        Enum.reduce(targets, acc, fn target, acc2 ->
          Map.update(acc2, target, 1, &(&1 + 1))
        end)
      end)

    queue = Enum.filter(node_ids, fn id -> Map.get(in_degree, id, 0) == 0 end)
    do_topo_sort(queue, in_degree, adjacency, node_map, [])
  end

  defp do_topo_sort([], _in_degree, _adjacency, _node_map, result) do
    Enum.reverse(result)
  end

  defp do_topo_sort([current | rest], in_degree, adjacency, node_map, result) do
    node = Map.fetch!(node_map, current)
    targets = Map.get(adjacency, current, [])

    {new_queue_items, new_in_degree} =
      Enum.reduce(targets, {[], in_degree}, fn target, {queue_acc, deg_acc} ->
        new_deg = Map.get(deg_acc, target, 0) - 1
        deg_acc = Map.put(deg_acc, target, new_deg)

        if new_deg == 0 do
          {[target | queue_acc], deg_acc}
        else
          {queue_acc, deg_acc}
        end
      end)

    do_topo_sort(rest ++ new_queue_items, new_in_degree, adjacency, node_map, [node | result])
  end
end
