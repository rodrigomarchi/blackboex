defmodule Blackboex.FlowExecutor.ReactorBuilder do
  @moduledoc """
  Builds a Reactor from a ParsedFlow.

  Converts the parsed flow definition into a Reactor with steps wired together
  via arguments. Each node becomes a Reactor step with the appropriate
  implementation module.

  ## Branch Gating

  Condition nodes output `%{branch: index, value: input, state: state}`.
  Nodes reachable (directly or transitively) from a Condition node are wrapped
  in a `BranchGate` step. The argument transform on the edge from the condition
  produces `%{output: :__branch_skipped__, state: state}` for non-matching
  branches. The BranchGate step checks for this sentinel and returns early
  without running the real node logic. Matching branches are delegated to the
  real node implementation unchanged.

  This centralises sentinel handling in `BranchGate` and the branch-gate
  argument transform, keeping individual node modules free of branching
  mechanics.
  """

  alias Blackboex.FlowExecutor.{ExecutionMiddleware, ParsedFlow, ParsedNode}

  alias Blackboex.FlowExecutor.Nodes.{
    BranchGate,
    Condition,
    Debug,
    Delay,
    ElixirCode,
    EndNode,
    Fail,
    ForEach,
    HttpRequest,
    SkipCondition,
    Start,
    SubFlow,
    WebhookWait
  }

  alias Reactor.{Argument, Builder}

  @max_nodes 100
  @max_edges 500

  @spec build(ParsedFlow.t(), keyword()) :: {:ok, Reactor.t()} | {:error, any()}
  def build(%ParsedFlow{} = parsed_flow, opts \\ []) do
    default_async? = Application.get_env(:blackboex, :flow_executor_async, true)
    async? = Keyword.get(opts, :async?, default_async?)

    with :ok <- validate_limits(parsed_flow) do
      reactor = Builder.new()
      condition_reachable = condition_reachable_node_ids(parsed_flow)

      with {:ok, reactor} <- Builder.add_input(reactor, :payload),
           {:ok, reactor} <- add_all_steps(reactor, parsed_flow, condition_reachable, async?),
           {:ok, reactor} <- set_return(reactor, parsed_flow, async?),
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

  # Returns the set of node IDs reachable from any condition node
  # (directly or transitively). These nodes are wrapped in BranchGate.
  @spec condition_reachable_node_ids(ParsedFlow.t()) :: MapSet.t(String.t())
  defp condition_reachable_node_ids(%ParsedFlow{nodes: nodes, adjacency: adjacency}) do
    condition_ids =
      nodes
      |> Enum.filter(&(&1.type == :condition))
      |> Enum.map(& &1.id)

    Enum.reduce(condition_ids, MapSet.new(), fn cond_id, acc ->
      reachable = bfs_reachable(cond_id, adjacency)
      MapSet.union(acc, reachable)
    end)
  end

  defp bfs_reachable(start_id, adjacency) do
    do_bfs([start_id], MapSet.new([start_id]), adjacency)
  end

  defp do_bfs([], visited, _adjacency), do: visited

  defp do_bfs([current | queue], visited, adjacency) do
    neighbours = Map.get(adjacency, current, [])

    {new_queue, new_visited} =
      Enum.reduce(neighbours, {queue, visited}, fn neighbour, {q, v} ->
        if MapSet.member?(v, neighbour) do
          {q, v}
        else
          {[neighbour | q], MapSet.put(v, neighbour)}
        end
      end)

    do_bfs(new_queue, new_visited, adjacency)
  end

  defp add_all_steps(reactor, %ParsedFlow{} = parsed_flow, condition_reachable, async?) do
    ordered = topological_sort(parsed_flow)

    Enum.reduce_while(ordered, {:ok, reactor}, fn node, {:ok, reactor} ->
      case add_node_step(reactor, node, parsed_flow, condition_reachable, async?) do
        {:ok, reactor} -> {:cont, {:ok, reactor}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :start} = node,
         _parsed_flow,
         _condition_reachable,
         _async?
       ) do
    schema_opts = start_schema_options(node.data)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {Start, schema_opts},
      [Argument.from_input(:payload, :payload)],
      async?: false
    )
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :elixir_code} = node,
         parsed_flow,
         condition_reachable,
         async?
       ) do
    code = node.data["code"] || ""
    timeout_ms = parse_timeout(node.data["timeout_ms"], 5_000)
    undo_code = Map.get(node.data, "undo_code")
    impl_opts = [code: code, timeout_ms: timeout_ms] |> maybe_add_opt(:undo_code, undo_code)

    {impl, opts} =
      if MapSet.member?(condition_reachable, node.id) do
        {BranchGate, [impl: ElixirCode, impl_options: impl_opts]}
      else
        {ElixirCode, impl_opts}
      end

    {impl, opts} = maybe_wrap_skip_condition({impl, opts}, node)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {impl, opts},
      [build_input_argument(node, parsed_flow)],
      async?: async?
    )
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :condition} = node,
         parsed_flow,
         _condition_reachable,
         async?
       ) do
    expression = node.data["expression"] || "0"
    timeout_ms = parse_timeout(node.data["timeout_ms"], 5_000)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {Condition, expression: expression, timeout_ms: timeout_ms},
      [build_input_argument(node, parsed_flow)],
      async?: async?
    )
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :sub_flow} = node,
         parsed_flow,
         condition_reachable,
         async?
       ) do
    flow_id = node.data["flow_id"] || ""
    timeout_ms = parse_timeout(node.data["timeout_ms"], 30_000)
    input_mapping = node.data["input_mapping"] || %{}
    impl_opts = [flow_id: flow_id, timeout_ms: timeout_ms, input_mapping: input_mapping]

    {impl, opts} =
      if MapSet.member?(condition_reachable, node.id) do
        {BranchGate, [impl: SubFlow, impl_options: impl_opts]}
      else
        {SubFlow, impl_opts}
      end

    {impl, opts} = maybe_wrap_skip_condition({impl, opts}, node)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {impl, opts},
      [build_input_argument(node, parsed_flow)],
      async?: async?
    )
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :http_request} = node,
         parsed_flow,
         condition_reachable,
         async?
       ) do
    undo_config = Map.get(node.data, "undo_config")

    impl_opts =
      [
        method: Map.get(node.data, "method", "GET"),
        url: Map.get(node.data, "url", ""),
        headers: Map.get(node.data, "headers", %{}),
        body_template: Map.get(node.data, "body_template", ""),
        timeout_ms: parse_timeout(node.data["timeout_ms"], 10_000),
        max_retries: Map.get(node.data, "max_retries", 3),
        auth_type: Map.get(node.data, "auth_type", "none"),
        auth_config: Map.get(node.data, "auth_config", %{}),
        expected_status: Map.get(node.data, "expected_status", [200, 201])
      ]
      |> maybe_add_opt(:undo_config, undo_config)
      |> maybe_add_test_plug(node.data)

    {impl, opts} =
      if MapSet.member?(condition_reachable, node.id) do
        {BranchGate, [impl: HttpRequest, impl_options: impl_opts]}
      else
        {HttpRequest, impl_opts}
      end

    {impl, opts} = maybe_wrap_skip_condition({impl, opts}, node)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {impl, opts},
      [build_input_argument(node, parsed_flow)],
      async?: async?
    )
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :delay} = node,
         parsed_flow,
         condition_reachable,
         async?
       ) do
    impl_opts = [
      duration_ms: parse_timeout(node.data["duration_ms"], 1_000),
      max_duration_ms: parse_timeout(node.data["max_duration_ms"], 60_000)
    ]

    {impl, opts} =
      if MapSet.member?(condition_reachable, node.id) do
        {BranchGate, [impl: Delay, impl_options: impl_opts]}
      else
        {Delay, impl_opts}
      end

    {impl, opts} = maybe_wrap_skip_condition({impl, opts}, node)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {impl, opts},
      [build_input_argument(node, parsed_flow)],
      async?: async?
    )
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :for_each} = node,
         parsed_flow,
         condition_reachable,
         async?
       ) do
    impl_opts = [
      source_expression: Map.get(node.data, "source_expression", ""),
      body_code: Map.get(node.data, "body_code", ""),
      item_variable: Map.get(node.data, "item_variable", "item"),
      accumulator: Map.get(node.data, "accumulator", "results"),
      batch_size: Map.get(node.data, "batch_size", 10),
      timeout_ms: parse_timeout(node.data["timeout_ms"], 5_000)
    ]

    {impl, opts} =
      if MapSet.member?(condition_reachable, node.id) do
        {BranchGate, [impl: ForEach, impl_options: impl_opts]}
      else
        {ForEach, impl_opts}
      end

    {impl, opts} = maybe_wrap_skip_condition({impl, opts}, node)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {impl, opts},
      [build_input_argument(node, parsed_flow)],
      async?: async?
    )
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :webhook_wait} = node,
         parsed_flow,
         condition_reachable,
         async?
       ) do
    impl_opts = [
      event_type: Map.get(node.data, "event_type", ""),
      timeout_ms: parse_timeout(node.data["timeout_ms"], 3_600_000),
      resume_path: Map.get(node.data, "resume_path", "")
    ]

    {impl, opts} =
      if MapSet.member?(condition_reachable, node.id) do
        {BranchGate, [impl: WebhookWait, impl_options: impl_opts]}
      else
        {WebhookWait, impl_opts}
      end

    {impl, opts} = maybe_wrap_skip_condition({impl, opts}, node)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {impl, opts},
      [build_input_argument(node, parsed_flow)],
      async?: async?
    )
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :debug} = node,
         parsed_flow,
         condition_reachable,
         async?
       ) do
    impl_opts = [
      expression: Map.get(node.data, "expression"),
      log_level: parse_log_level(node.data),
      state_key: Map.get(node.data, "state_key", "debug"),
      timeout_ms: parse_timeout(node.data["timeout_ms"], 5_000)
    ]

    {impl, opts} =
      if MapSet.member?(condition_reachable, node.id) do
        {BranchGate, [impl: Debug, impl_options: impl_opts]}
      else
        {Debug, impl_opts}
      end

    {impl, opts} = maybe_wrap_skip_condition({impl, opts}, node)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {impl, opts},
      [build_input_argument(node, parsed_flow)],
      async?: async?
    )
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :fail} = node,
         parsed_flow,
         condition_reachable,
         async?
       ) do
    impl_opts = [
      message: Map.get(node.data, "message", ""),
      include_state: Map.get(node.data, "include_state", false),
      timeout_ms: parse_timeout(node.data["timeout_ms"], 5_000)
    ]

    {impl, opts} =
      if MapSet.member?(condition_reachable, node.id) do
        {BranchGate, [impl: Fail, impl_options: impl_opts]}
      else
        {Fail, impl_opts}
      end

    {impl, opts} = maybe_wrap_skip_condition({impl, opts}, node)

    Builder.add_step(
      reactor,
      step_name(node.id),
      {impl, opts},
      [build_input_argument(node, parsed_flow)],
      async?: async?
    )
  end

  defp add_node_step(
         reactor,
         %ParsedNode{type: :end} = node,
         parsed_flow,
         condition_reachable,
         async?
       ) do
    schema_opts = end_schema_options(node.data)

    {impl, opts} =
      if MapSet.member?(condition_reachable, node.id) do
        {BranchGate, [impl: EndNode, impl_options: schema_opts]}
      else
        {EndNode, schema_opts}
      end

    Builder.add_step(
      reactor,
      step_name(node.id),
      {impl, opts},
      [build_input_argument(node, parsed_flow)],
      async?: async?
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

  defp set_return(reactor, %ParsedFlow{end_node_ids: [end_id]}, _async?) do
    Builder.return(reactor, step_name(end_id))
  end

  defp set_return(reactor, %ParsedFlow{end_node_ids: end_ids}, _async?)
       when length(end_ids) > 1 do
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

  defp set_return(_reactor, _parsed_flow, _async?) do
    {:error, "no end node found to set as return"}
  end

  # Use a bounded set of atom names — node IDs are validated to match /^n\d+$/
  # and capped at @max_nodes, so atom table growth is bounded.
  defp step_name(node_id) when is_binary(node_id) do
    String.to_atom("node_#{node_id}")
  end

  defp parse_log_level(%{"log_level" => "debug"}), do: :debug
  defp parse_log_level(%{"log_level" => "warning"}), do: :warning
  defp parse_log_level(_), do: :info

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

  # ── Schema options helpers ──

  defp start_schema_options(data) do
    opts = []
    opts = maybe_add_opt(opts, :payload_schema, data["payload_schema"])
    maybe_add_opt(opts, :state_schema, data["state_schema"])
  end

  defp end_schema_options(data) do
    opts = []
    opts = maybe_add_opt(opts, :response_schema, data["response_schema"])
    maybe_add_opt(opts, :response_mapping, data["response_mapping"])
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, []), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  # Wraps {impl, opts} in SkipCondition when the node has a valid skip_condition.
  # Order: impl → BranchGate (if condition-reachable) → SkipCondition (outermost).
  @spec maybe_wrap_skip_condition({module(), keyword()}, ParsedNode.t()) ::
          {module(), keyword()}
  defp maybe_wrap_skip_condition(
         {impl, opts},
         %ParsedNode{data: %{"skip_condition" => skip_cond}}
       )
       when is_binary(skip_cond) and skip_cond != "" do
    {SkipCondition, [impl: impl, impl_options: opts, skip_expression: skip_cond]}
  end

  defp maybe_wrap_skip_condition(pair, _node), do: pair

  # Allows injecting a Req.Test plug via node data for E2E testing.
  @spec maybe_add_test_plug(keyword(), map()) :: keyword()
  defp maybe_add_test_plug(opts, %{"plug" => plug}) when not is_nil(plug),
    do: opts ++ [plug: plug, retry: false]

  defp maybe_add_test_plug(opts, _data), do: opts
end
