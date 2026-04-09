defmodule Blackboex.FlowExecutor.Nodes.Start do
  @moduledoc """
  Reactor step for the Start node.
  Receives the flow payload and passes it through as the first output.

  Options (from node data via ReactorBuilder):
    - `payload_schema` — validates incoming payload against schema
    - `state_schema` — initializes state variables from schema initial values
  """

  use Reactor.Step

  alias Blackboex.FlowExecutor.SchemaValidator

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(arguments, _context, options) do
    payload = arguments.payload
    payload_schema = Keyword.get(options, :payload_schema)
    state_schema = Keyword.get(options, :state_schema)

    with :ok <- validate_payload(payload, payload_schema) do
      initial_state = build_state(state_schema)
      {:ok, %{output: payload, state: initial_state}}
    end
  end

  defp validate_payload(_payload, nil), do: :ok
  defp validate_payload(_payload, []), do: :ok

  defp validate_payload(payload, schema) do
    case SchemaValidator.validate_payload(payload, schema) do
      {:ok, _} -> :ok
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  defp build_state(nil), do: %{}
  defp build_state([]), do: %{}
  defp build_state(schema), do: SchemaValidator.build_initial_state(schema)

  defp format_errors(errors) do
    details = Enum.map_join(errors, "; ", fn e -> "#{e.field} #{e.message}" end)
    "Payload validation failed: #{details}"
  end
end
