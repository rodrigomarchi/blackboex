defmodule Blackboex.FlowExecutor.Nodes.BranchGate do
  @moduledoc """
  Reactor step that acts as a gate for condition branches.

  When a node is directly downstream of a Condition node, it is wrapped in a
  BranchGate step. The BranchGate checks whether the incoming input is the
  branch-skipped sentinel. If so, it returns the sentinel immediately without
  running the real node logic. If not, it delegates to the real node implementation.

  This centralises all `__branch_skipped__` handling in one place, keeping
  individual node implementations free of sentinel awareness.

  Options (required):
    - `:impl` — the real node step module (e.g. `ElixirCode`, `EndNode`)
    - `:impl_options` — keyword list of options forwarded to the impl's `run/3`
  """

  use Reactor.Step

  alias Blackboex.FlowExecutor.Nodes.Helpers

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, any()}
  def run(arguments, context, options) do
    impl = Keyword.fetch!(options, :impl)
    impl_options = Keyword.get(options, :impl_options, [])

    {input, state} = Helpers.extract_input_and_state(arguments)

    if input == :__branch_skipped__ do
      {:ok, %{output: :__branch_skipped__, state: state}}
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
end
