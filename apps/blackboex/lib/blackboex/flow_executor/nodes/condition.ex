defmodule Blackboex.FlowExecutor.Nodes.Condition do
  @moduledoc """
  Reactor step for Condition nodes.
  Evaluates an expression that returns a branch index (0-based integer).
  The output includes the branch index, the input value, and the current state.

  Wrapped in a Task with timeout to prevent infinite loops.
  """

  use Reactor.Step

  alias Blackboex.FlowExecutor.Nodes.Helpers

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, any()}
  def run(arguments, _context, options) do
    expression = Keyword.fetch!(options, :expression)
    timeout_ms = Keyword.get(options, :timeout_ms, 5_000)
    {input, state} = Helpers.extract_input_and_state(arguments)

    if input == :__branch_skipped__ do
      # This condition sits on an already-skipped branch. Propagate the skip to
      # every downstream port by returning a branch index that cannot match any
      # edge's source_port (branch_gate/2 in ReactorBuilder treats a mismatch
      # as :__branch_skipped__).
      {:ok, %{branch: :__branch_skipped__, value: :__branch_skipped__, state: state}}
    else
      execute_with_timeout(expression, input, state, timeout_ms)
    end
  end

  @impl true
  @spec compensate(any(), Reactor.inputs(), Reactor.context(), keyword()) :: :ok | :retry
  def compensate(reason, _arguments, _context, _options) do
    case reason do
      %ErlangError{original: :timeout} -> :retry
      "execution timed out" <> _ -> :retry
      _ -> :ok
    end
  end

  @impl true
  @spec backoff(any(), Reactor.inputs(), Reactor.context(), keyword()) :: non_neg_integer()
  def backoff(_reason, _arguments, context, _options) do
    retry_count = Map.get(context, :current_try, 0)
    min(round(:math.pow(2, retry_count) * 500), 10_000)
  end

  defp execute_with_timeout(expression, input, state, timeout_ms) do
    Helpers.execute_with_timeout(
      fn ->
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
      end,
      timeout_ms
    )
  end
end
