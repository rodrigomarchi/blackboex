defmodule Blackboex.FlowExecutor.Nodes.Fail do
  @moduledoc """
  Reactor step for Fail/Error nodes.
  Evaluates a user-defined message expression and returns an error tuple,
  unconditionally terminating the flow with that message.

  The message expression has access to `input` and `state` bindings.
  If `include_state: true`, the current state map is appended to the message.
  """

  use Reactor.Step

  alias Blackboex.FlowExecutor.Nodes.Helpers

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:error, String.t()}
  def run(arguments, _context, options) do
    message_expr = Keyword.fetch!(options, :message)
    include_state = Keyword.get(options, :include_state, false)
    timeout_ms = Keyword.get(options, :timeout_ms, 5_000)
    {input, state} = Helpers.extract_input_and_state(arguments)
    evaluate_message(message_expr, input, state, include_state, timeout_ms)
  end

  defp evaluate_message(message_expr, input, state, include_state, timeout_ms) do
    result =
      Helpers.execute_with_timeout(
        fn ->
          try do
            bindings = [input: input, state: state]
            {value, _bindings} = Code.eval_string(message_expr, bindings)
            {:ok, to_string(value)}
          rescue
            e -> {:error, Exception.message(e)}
          end
        end,
        timeout_ms
      )

    case result do
      {:ok, msg} when include_state ->
        {:error, "#{msg}\nstate: #{inspect(state)}"}

      {:ok, msg} ->
        {:error, msg}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
