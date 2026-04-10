defmodule Blackboex.FlowExecutor.Nodes.Debug do
  @moduledoc "Debug node — evaluates an expression, logs it, and passes input through unchanged."

  use Reactor.Step

  alias Blackboex.FlowExecutor.Nodes.Helpers

  require Logger

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()}
  def run(arguments, _context, options) do
    {input, state} = Helpers.extract_input_and_state(arguments)

    expression = Keyword.get(options, :expression)
    log_level = Keyword.get(options, :log_level, :info)
    state_key = Keyword.get(options, :state_key, "debug")
    timeout_ms = Keyword.get(options, :timeout_ms, 5_000)

    debug_value = evaluate_expression(expression, input, state, timeout_ms)
    log_debug(log_level, debug_value)

    new_state =
      if is_nil(expression) do
        state
      else
        Map.put(state, state_key, debug_value)
      end

    {:ok, Helpers.wrap_output(input, new_state)}
  end

  @spec evaluate_expression(String.t() | nil, any(), map(), pos_integer()) :: any()
  defp evaluate_expression(nil, input, _state, _timeout_ms), do: inspect(input)

  defp evaluate_expression(expression, input, state, timeout_ms) do
    case Helpers.execute_with_timeout(
           fn ->
             try do
               bindings = [input: input, state: state]
               {result, _} = Code.eval_string(expression, bindings)
               {:ok, result}
             rescue
               e -> {:ok, "debug expression error: #{Exception.message(e)}"}
             end
           end,
           timeout_ms
         ) do
      {:ok, value} -> value
      {:error, reason} -> "debug timeout: #{reason}"
    end
  end

  @spec log_debug(atom(), any()) :: :ok
  defp log_debug(level, value) do
    message = "[FlowDebug] #{inspect(value)}"
    Logger.log(level, message)
  end
end
