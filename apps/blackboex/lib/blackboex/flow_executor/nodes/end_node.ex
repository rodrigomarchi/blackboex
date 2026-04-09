defmodule Blackboex.FlowExecutor.Nodes.EndNode do
  @moduledoc """
  Reactor step for the End node.
  Receives the final input and state, produces the flow output.

  Options (from node data via ReactorBuilder):
    - `response_schema` — defines expected response fields
    - `response_mapping` — maps state variables to response fields
  """

  use Reactor.Step

  alias Blackboex.FlowExecutor.Nodes.Helpers
  alias Blackboex.FlowExecutor.SchemaValidator

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(arguments, _context, options) do
    {input, state} = Helpers.extract_input_and_state(arguments)
    build_output(input, state, options)
  end

  defp build_output(input, state, options) do
    response_schema = Keyword.get(options, :response_schema)
    response_mapping = Keyword.get(options, :response_mapping)

    if has_mapping?(response_mapping) do
      case SchemaValidator.build_response(state, response_schema, response_mapping) do
        {:ok, response} -> {:ok, %{output: response, state: state}}
        {:error, errors} -> {:error, format_errors(errors)}
      end
    else
      {:ok, %{output: input, state: state}}
    end
  end

  defp has_mapping?(nil), do: false
  defp has_mapping?([]), do: false
  defp has_mapping?(mapping) when is_list(mapping), do: true

  defp format_errors(errors) do
    details = Enum.map_join(errors, "; ", fn e -> "#{e.field} #{e.message}" end)
    "Response mapping failed: #{details}"
  end
end
