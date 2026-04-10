defmodule Blackboex.FlowExecutor.Nodes.SkipCondition do
  @moduledoc """
  Reactor step wrapper that conditionally skips a node.

  When the skip_condition expression evaluates to true, the node is skipped
  and input passes through unchanged. Otherwise, delegates to the real
  node implementation.

  Options (required):
    - `:skip_expression` — Elixir expression string; evaluated with `input` and `state` bindings
    - `:impl` — the real node step module (e.g. `ElixirCode`, `EndNode`)
    - `:impl_options` — keyword list of options forwarded to the impl's `run/3`

  Errors in the skip expression default to not skipping (safe failure mode).
  """

  use Reactor.Step

  alias Blackboex.FlowExecutor.Nodes.Helpers

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, any()}
  def run(arguments, context, options) do
    skip_expression = Keyword.fetch!(options, :skip_expression)
    impl = Keyword.fetch!(options, :impl)
    impl_options = Keyword.get(options, :impl_options, [])
    timeout_ms = Keyword.get(options, :timeout_ms, 5_000)

    {input, state} = Helpers.extract_input_and_state(arguments)

    if should_skip?(skip_expression, input, state, timeout_ms) do
      {:ok, Helpers.wrap_output(input, state)}
    else
      impl.run(arguments, context, impl_options)
    end
  end

  @impl true
  @spec compensate(any(), Reactor.inputs(), Reactor.context(), keyword()) :: :ok | :retry
  def compensate(reason, arguments, context, options) do
    impl = Keyword.fetch!(options, :impl)
    impl_options = Keyword.get(options, :impl_options, [])

    if function_exported?(impl, :compensate, 4) do
      impl.compensate(reason, arguments, context, impl_options)
    else
      :ok
    end
  end

  @impl true
  @spec backoff(any(), Reactor.inputs(), Reactor.context(), keyword()) :: :now | pos_integer()
  def backoff(reason, arguments, context, options) do
    impl = Keyword.fetch!(options, :impl)
    impl_options = Keyword.get(options, :impl_options, [])

    if function_exported?(impl, :backoff, 4) do
      impl.backoff(reason, arguments, context, impl_options)
    else
      :now
    end
  end

  @impl true
  @spec undo(any(), Reactor.inputs(), Reactor.context(), keyword()) :: :ok | {:error, any()}
  def undo(value, arguments, context, options) do
    impl = Keyword.fetch!(options, :impl)
    impl_options = Keyword.get(options, :impl_options, [])

    if function_exported?(impl, :undo, 4) do
      impl.undo(value, arguments, context, impl_options)
    else
      :ok
    end
  end

  @spec should_skip?(String.t(), any(), map(), pos_integer()) :: boolean()
  defp should_skip?(expression, input, state, timeout_ms) do
    case Helpers.execute_with_timeout(
           fn ->
             try do
               bindings = [input: input, state: state]
               {result, _} = Code.eval_string(expression, bindings)
               {:ok, result == true}
             rescue
               _ -> {:ok, false}
             end
           end,
           timeout_ms
         ) do
      {:ok, skip?} -> skip?
      {:error, _} -> false
    end
  end
end
