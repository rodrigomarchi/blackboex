defmodule Blackboex.FlowExecutor.Nodes.EndNode do
  @moduledoc """
  Reactor step for the End node.
  Receives the final input and state, produces the flow output.
  """

  use Reactor.Step

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()}
  def run(arguments, _context, _options) do
    {input, state} = extract_input_and_state(arguments)

    # Skip if branch was gated
    if input == :__branch_skipped__ do
      {:ok, %{output: :__branch_skipped__, state: state}}
    else
      {:ok, %{output: input, state: state}}
    end
  end

  defp extract_input_and_state(%{prev_result: %{output: output, state: state}}),
    do: {output, state}

  defp extract_input_and_state(%{prev_result: %{value: value, state: state}}),
    do: {value, state}

  defp extract_input_and_state(%{input: input}),
    do: {input, %{}}
end
