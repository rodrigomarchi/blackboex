defmodule Blackboex.FlowExecutor.Nodes.Start do
  @moduledoc """
  Reactor step for the Start node.
  Receives the flow payload and passes it through as the first output.
  """

  use Reactor.Step

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()}
  def run(arguments, _context, _options) do
    payload = arguments.payload
    {:ok, %{output: payload, state: %{}}}
  end
end
