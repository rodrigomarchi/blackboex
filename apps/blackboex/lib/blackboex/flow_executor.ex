defmodule Blackboex.FlowExecutor do
  @moduledoc """
  Public facade for executing flows.

  Parses a flow's BlackboexFlow definition, validates code, resolves project
  env vars (`{{env.X}}` / legacy `{{secrets.X}}`), builds a Reactor, and
  executes it. Supports both sync and async execution modes.
  """

  alias Blackboex.FlowExecutions

  alias Blackboex.FlowExecutor.{
    BlackboexFlow,
    CodeValidator,
    DefinitionParser,
    EnvResolver,
    ReactorBuilder
  }

  alias Blackboex.Flows.Flow
  alias Blackboex.ProjectEnvVars
  alias Blackboex.Workers.FlowExecutionWorker

  require Logger

  # Reactor.run/4 returns {:halted, reactor} when a step (e.g. webhook_wait) halts,
  # but its @spec omits this variant. Suppress the resulting Dialyzer pattern_match warning.
  @dialyzer {:no_match, run: 3}

  @spec run(Flow.t(), map(), Ecto.UUID.t() | nil) ::
          {:ok, map()} | {:halted, map()} | {:error, any()}
  def run(%Flow{} = flow, input, execution_id \\ nil) do
    with :ok <- BlackboexFlow.validate(flow.definition || %{}),
         {:ok, resolved_def} <- resolve_env(flow),
         {:ok, parsed} <- DefinitionParser.parse(resolved_def),
         :ok <- CodeValidator.validate_flow(parsed),
         {:ok, reactor} <- ReactorBuilder.build(parsed) do
      env_map = load_env_map(flow.project_id)

      context =
        build_context(parsed, execution_id, flow.organization_id, flow.project_id, env_map)

      case Reactor.run(reactor, %{payload: input}, context) do
        {:ok, result} ->
          {:ok, result}

        {:halted, _reactor} ->
          {:halted, %{execution_id: execution_id}}

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
          # Extract the output from the EndNode result (%{output: X, state: Y}).
          output = extract_output(result)
          execution = FlowExecutions.get_execution(execution.id)
          duration_ms = compute_duration(execution)
          FlowExecutions.complete_execution(execution, wrap_for_db(output), duration_ms)
          {:ok, %{output: output, execution_id: execution.id, duration_ms: duration_ms}}

        {:halted, _halt_info} ->
          # webhook_wait node already set the execution to "waiting" status.
          {:ok, %{halted: true, execution_id: execution.id}}

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

  defp resolve_env(%Flow{definition: nil}), do: {:ok, %{}}
  defp resolve_env(%Flow{definition: def_map}) when def_map == %{}, do: {:ok, def_map}

  defp resolve_env(%Flow{definition: definition, project_id: project_id}) do
    EnvResolver.resolve(definition, project_id)
  end

  defp load_env_map(nil), do: %{}
  defp load_env_map(project_id), do: ProjectEnvVars.load_runtime_map(project_id)

  defp build_context(parsed, execution_id, organization_id, project_id, env_map) do
    node_map =
      Map.new(parsed.nodes, fn node ->
        {String.to_atom("node_#{node.id}"), %{id: node.id, type: node.type}}
      end)

    %{
      execution_id: execution_id,
      node_map: node_map,
      organization_id: organization_id,
      project_id: project_id,
      env: env_map
    }
  end

  defp compute_duration(%{started_at: %DateTime{} = started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
  end

  defp compute_duration(%{inserted_at: %NaiveDateTime{} = inserted_at}) do
    NaiveDateTime.diff(DateTime.to_naive(DateTime.utc_now()), inserted_at, :millisecond)
  end

  defp compute_duration(_), do: 0

  # EndNode returns %{output: value, state: state} — extract just the output.
  defp extract_output(%{output: output}), do: output
  defp extract_output(result), do: result

  # FlowExecution.output is a :map field — wrap non-map values for DB storage.
  defp wrap_for_db(output) when is_map(output), do: output
  defp wrap_for_db(output), do: %{"value" => output}

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
