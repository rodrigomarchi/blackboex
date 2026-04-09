defmodule Blackboex.FlowExecutor.Nodes.SubFlow do
  @moduledoc "Sub-flow node — executes another flow as a nested step."

  use Reactor.Step

  alias Blackboex.FlowExecutor.Nodes.Helpers

  @max_depth 5

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, any()}
  def run(arguments, context, options) do
    {input, state} = Helpers.extract_input_and_state(arguments)

    flow_id = Keyword.fetch!(options, :flow_id)
    input_mapping = Keyword.get(options, :input_mapping, %{})
    timeout_ms = Keyword.get(options, :timeout_ms, 30_000)
    organization_id = Map.get(context, :organization_id)

    depth = Process.get(:sub_flow_depth, 0)

    if depth >= @max_depth do
      {:error, "sub-flow depth limit exceeded (max #{@max_depth})"}
    else
      execute_sub_flow(flow_id, organization_id, input, state, input_mapping, timeout_ms, depth)
    end
  end

  # ── Private ──────────────────────────────────────────────────

  @spec execute_sub_flow(
          String.t(),
          String.t() | nil,
          any(),
          map(),
          map(),
          pos_integer(),
          non_neg_integer()
        ) :: {:ok, map()} | {:error, any()}
  defp execute_sub_flow(flow_id, organization_id, input, state, input_mapping, timeout_ms, depth) do
    with {:ok, flow} <- load_flow(organization_id, flow_id),
         {:ok, sub_payload} <- build_payload(input_mapping, input, state) do
      Helpers.execute_with_timeout(
        fn ->
          # Set depth in the spawned task's process so nested SubFlow nodes see it.
          Process.put(:sub_flow_depth, depth + 1)
          Blackboex.FlowExecutor.run(flow, sub_payload)
        end,
        timeout_ms
      )
      |> case do
        {:ok, result} ->
          sub_output = extract_output(result)
          new_state = Map.put(state, "sub_flow_result", sub_output)
          {:ok, Helpers.wrap_output(sub_output, new_state)}

        {:error, _} = error ->
          error
      end
    end
  end

  @spec load_flow(String.t() | nil, String.t()) ::
          {:ok, Blackboex.Flows.Flow.t()} | {:error, String.t()}
  defp load_flow(organization_id, flow_id)
       when is_binary(organization_id) and is_binary(flow_id) and flow_id != "" do
    case Blackboex.Flows.get_flow(organization_id, flow_id) do
      nil -> {:error, "sub-flow not found: #{flow_id}"}
      flow -> {:ok, flow}
    end
  end

  defp load_flow(nil, _flow_id), do: {:error, "sub-flow: organization_id not in context"}
  defp load_flow(_org_id, _flow_id), do: {:error, "sub-flow: flow_id is required"}

  @spec build_payload(map(), any(), map()) :: {:ok, any()} | {:error, String.t()}
  defp build_payload(input_mapping, input, _state) when map_size(input_mapping) == 0 do
    {:ok, input}
  end

  defp build_payload(input_mapping, input, state) do
    payload =
      Enum.reduce(input_mapping, %{}, fn {key, expression}, acc ->
        {value, _} = Code.eval_string(expression, input: input, state: state)
        Map.put(acc, key, value)
      end)

    {:ok, payload}
  rescue
    e -> {:error, "input_mapping evaluation failed: #{Exception.message(e)}"}
  end

  @spec extract_output(map() | any()) :: any()
  defp extract_output(%{output: output}), do: output
  defp extract_output(result) when is_map(result), do: result
  defp extract_output(result), do: result
end
