defmodule Blackboex.FlowExecutor.ReactorBuilder.Collector do
  @moduledoc """
  Reactor step that collects results from multiple end nodes in a branching flow.
  Returns the first non-skipped end node result.
  """

  use Reactor.Step

  @doc false
  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, any()}
  def run(arguments, _context, _options) do
    result =
      arguments
      |> Map.values()
      |> Enum.find(fn
        %{output: :__branch_skipped__} -> false
        _ -> true
      end)

    case result do
      nil ->
        {:error,
         "no branch produced a result — all end nodes were skipped. " <>
           "Check that the condition expression returns a valid branch index (0-based) " <>
           "matching the connected output ports."}

      value ->
        {:ok, value}
    end
  end
end
