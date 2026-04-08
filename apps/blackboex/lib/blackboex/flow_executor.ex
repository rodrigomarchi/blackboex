defmodule Blackboex.FlowExecutor do
  @moduledoc """
  Public facade for executing flows.

  Parses a flow's BlackboexFlow definition, validates code, resolves secrets,
  builds a Reactor, and executes it. Supports both sync and async execution modes.
  """

  alias Blackboex.FlowExecutions

  alias Blackboex.FlowExecutor.{
    BlackboexFlow,
    CodeValidator,
    DefinitionParser,
    ReactorBuilder,
    SecretResolver
  }

  alias Blackboex.Flows.Flow
  alias Blackboex.Workers.FlowExecutionWorker

  require Logger

  @spec run(Flow.t(), map(), Ecto.UUID.t() | nil) ::
          {:ok, map()} | {:error, any()}
  def run(%Flow{} = flow, input, execution_id \\ nil) do
    with :ok <- BlackboexFlow.validate(flow.definition || %{}),
         {:ok, resolved_def} <- resolve_secrets(flow),
         {:ok, parsed} <- DefinitionParser.parse(resolved_def),
         :ok <- CodeValidator.validate_flow(parsed),
         {:ok, reactor} <- ReactorBuilder.build(parsed) do
      context = build_context(parsed, execution_id)

      case Reactor.run(reactor, %{payload: input}, context) do
        {:ok, result} ->
          {:ok, result}

        {:error, reason} ->
          {:error, format_error(reason)}
      end
    end
  end

  @spec execute_sync(Flow.t(), map()) ::
          {:ok, map()} | {:error, any()}
  def execute_sync(%Flow{} = flow, input) do
    with {:ok, execution} <- FlowExecutions.create_execution(flow, input) do
      case run(flow, input, execution.id) do
        {:ok, result} ->
          # Middleware handles NodeExecution persistence and PubSub.
          # We only update the top-level FlowExecution completion here.
          execution = FlowExecutions.get_execution(execution.id)
          duration_ms = compute_duration(execution)
          FlowExecutions.complete_execution(execution, result, duration_ms)
          {:ok, %{output: result, execution_id: execution.id, duration_ms: duration_ms}}

        {:error, reason} ->
          error_msg = format_error(reason)
          execution = FlowExecutions.get_execution(execution.id)
          FlowExecutions.fail_execution(execution, error_msg)
          {:error, %{error: error_msg, execution_id: execution.id}}
      end
    end
  end

  @spec execute_async(Flow.t(), map()) ::
          {:ok, map()} | {:error, any()}
  def execute_async(%Flow{} = flow, input) do
    with {:ok, execution} <- FlowExecutions.create_execution(flow, input) do
      %{execution_id: execution.id, flow_id: flow.id}
      |> FlowExecutionWorker.new()
      |> Oban.insert()

      {:ok, %{execution_id: execution.id}}
    end
  end

  # ── Private ──────────────────────────────────────────────────

  defp resolve_secrets(%Flow{definition: nil}), do: {:ok, %{}}
  defp resolve_secrets(%Flow{definition: def_map}) when def_map == %{}, do: {:ok, def_map}

  defp resolve_secrets(%Flow{definition: definition, organization_id: org_id}) do
    SecretResolver.resolve(definition, org_id)
  end

  defp build_context(parsed, execution_id) do
    node_map =
      Map.new(parsed.nodes, fn node ->
        {String.to_atom("node_#{node.id}"), %{id: node.id, type: node.type}}
      end)

    %{
      execution_id: execution_id,
      node_map: node_map
    }
  end

  defp compute_duration(%{started_at: %DateTime{} = started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
  end

  defp compute_duration(%{inserted_at: %NaiveDateTime{} = inserted_at}) do
    NaiveDateTime.diff(DateTime.to_naive(DateTime.utc_now()), inserted_at, :millisecond)
  end

  defp compute_duration(_), do: 0

  defp format_error(%{errors: errors}) when is_list(errors) do
    errors
    |> Enum.map(&format_error/1)
    |> Enum.join("; ")
  end

  defp format_error(%{error: error}), do: format_error(error)
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
