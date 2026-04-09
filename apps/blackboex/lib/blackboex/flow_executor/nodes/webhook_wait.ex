defmodule Blackboex.FlowExecutor.Nodes.WebhookWait do
  @moduledoc "Webhook wait node — halts flow execution until external callback arrives."

  use Reactor.Step

  alias Blackboex.FlowExecutor.Nodes.Helpers

  @impl true
  @spec run(Reactor.inputs(), Reactor.context(), keyword()) ::
          {:halt, map()} | {:ok, map()}
  def run(arguments, context, options) do
    {input, state} = Helpers.extract_input_and_state(arguments)

    event_type = Keyword.fetch!(options, :event_type)
    _timeout_ms = Keyword.get(options, :timeout_ms, 3_600_000)
    resume_path = Keyword.get(options, :resume_path, "")

    execution_id = Map.get(context, :execution_id)

    if execution_id do
      case Blackboex.FlowExecutions.get_execution(execution_id) do
        nil -> :ok
        execution -> Blackboex.FlowExecutions.halt_execution(execution, event_type)
      end
    end

    {:halt,
     %{
       event_type: event_type,
       resume_path: resume_path,
       input: input,
       state: state,
       execution_id: execution_id
     }}
  end
end
