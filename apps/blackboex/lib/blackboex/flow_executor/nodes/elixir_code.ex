defmodule Blackboex.FlowExecutor.Nodes.ElixirCode do
  @moduledoc """
  Reactor step for Elixir Code nodes.
  Evaluates user-provided Elixir code with `input` and `state` bindings.

  The code can return:
  - A plain value → output is that value, state unchanged
  - A `{output, new_state}` tuple where new_state is a map → output + state updated
  """

  use Reactor.Step

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, any()}
  def run(arguments, _context, options) do
    code = Keyword.fetch!(options, :code)
    timeout_ms = Keyword.get(options, :timeout_ms, 5_000)
    {input, state} = extract_input_and_state(arguments)

    # Skip if branch was gated
    if input == :__branch_skipped__ do
      {:ok, %{output: :__branch_skipped__, state: state}}
    else
      execute_with_timeout(code, input, state, timeout_ms)
    end
  end

  defp execute_with_timeout(code, input, state, timeout_ms) do
    task =
      Task.async(fn ->
        try do
          bindings = [input: input, state: state]
          {result, _bindings} = Code.eval_string(code, bindings)
          normalize_result(result, state)
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, output, new_state}} -> {:ok, %{output: output, state: new_state}}
      {:ok, {:error, reason}} -> {:error, reason}
      nil -> {:error, "code execution timed out after #{timeout_ms}ms"}
    end
  end

  defp normalize_result({output, new_state}, _old_state) when is_map(new_state) do
    {:ok, output, new_state}
  end

  defp normalize_result({output, _non_map}, old_state) do
    # Non-map state in tuple: ignore the state update, keep old state
    {:ok, output, old_state}
  end

  defp normalize_result(output, old_state) do
    {:ok, output, old_state}
  end

  defp extract_input_and_state(%{prev_result: %{output: output, state: state}}),
    do: {output, state}

  defp extract_input_and_state(%{prev_result: %{value: value, state: state}}),
    do: {value, state}

  defp extract_input_and_state(%{prev_result: %{value: value}}),
    do: {value, %{}}

  defp extract_input_and_state(%{input: input}),
    do: {input, %{}}
end
