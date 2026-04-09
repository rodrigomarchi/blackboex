defmodule Blackboex.FlowExecutor.Nodes.ElixirCode do
  @moduledoc """
  Reactor step for Elixir Code nodes.
  Evaluates user-provided Elixir code with `input` and `state` bindings.

  The code can return:
  - A plain value → output is that value, state unchanged
  - A `{output, new_state}` tuple where new_state is a map → output + state updated
  """

  use Reactor.Step

  alias Blackboex.FlowExecutor.Nodes.Helpers

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, any()}
  def run(arguments, _context, options) do
    code = Keyword.fetch!(options, :code)
    timeout_ms = Keyword.get(options, :timeout_ms, 5_000)
    {input, state} = Helpers.extract_input_and_state(arguments)
    execute_with_timeout(code, input, state, timeout_ms)
  end

  defp execute_with_timeout(code, input, state, timeout_ms) do
    Helpers.execute_with_timeout(
      fn ->
        try do
          bindings = [input: input, state: state]
          {result, _bindings} = Code.eval_string(code, bindings)

          {:ok, output, new_state} = normalize_result(result, state)
          {:ok, %{output: output, state: new_state}}
        rescue
          e -> {:error, Exception.message(e)}
        end
      end,
      timeout_ms
    )
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
end
