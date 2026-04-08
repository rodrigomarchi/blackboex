defmodule Blackboex.FlowExecutor.Nodes.Condition do
  @moduledoc """
  Reactor step for Condition nodes.
  Evaluates an expression that returns a branch index (0-based integer).
  The output includes the branch index, the input value, and the current state.

  Wrapped in a Task with timeout to prevent infinite loops.
  """

  use Reactor.Step

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, any()}
  def run(arguments, _context, options) do
    expression = Keyword.fetch!(options, :expression)
    timeout_ms = Keyword.get(options, :timeout_ms, 5_000)
    {input, state} = extract_input_and_state(arguments)

    # Skip if branch was gated
    if input == :__branch_skipped__ do
      {:ok, %{branch: -1, value: :__branch_skipped__, state: state}}
    else
      execute_with_timeout(expression, input, state, timeout_ms)
    end
  end

  defp execute_with_timeout(expression, input, state, timeout_ms) do
    task =
      Task.async(fn ->
        try do
          bindings = [input: input, state: state]
          {result, _bindings} = Code.eval_string(expression, bindings)

          case result do
            index when is_integer(index) and index >= 0 ->
              {:ok, %{branch: index, value: input, state: state}}

            other ->
              {:error,
               "condition expression must return a non-negative integer, got: #{inspect(other)}"}
          end
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, "condition expression timed out after #{timeout_ms}ms"}
    end
  end

  defp extract_input_and_state(%{prev_result: %{output: output, state: state}}),
    do: {output, state}

  defp extract_input_and_state(%{prev_result: %{value: value, state: state}}),
    do: {value, state}

  defp extract_input_and_state(%{input: input}),
    do: {input, %{}}
end
