defmodule Blackboex.FlowExecutor.ExecutionMiddleware do
  @moduledoc """
  Reactor middleware that persists node-level execution state and broadcasts progress.

  Responsibilities:
  - Creates/updates NodeExecution records on step start/complete/error
  - Updates FlowExecution.shared_state when nodes update state
  - Broadcasts progress via PubSub on "flow_execution:{id}" topic
  - Marks FlowExecution as "running" on init

  Note: FlowExecution completion/failure is handled by the caller (FlowExecutor facade
  or FlowExecutionWorker), NOT by this middleware, to avoid double-writes.
  """

  use Reactor.Middleware

  alias Blackboex.FlowExecutions
  alias Phoenix.PubSub

  @impl true
  @spec init(Reactor.context()) :: {:ok, Reactor.context()} | {:error, any()}
  def init(context) do
    mark_running(context[:execution_id])
    {:ok, context}
  end

  @impl true
  @spec complete(any(), Reactor.context()) :: {:ok, any()} | {:error, any()}
  def complete(result, context) do
    broadcast(
      context[:execution_id],
      {:flow_completed, %{execution_id: context[:execution_id], result: result}}
    )

    {:ok, result}
  end

  @impl true
  @spec error(any(), Reactor.context()) :: :ok | {:error, any()}
  def error(errors, context) do
    error_msg = format_errors(errors)

    broadcast(
      context[:execution_id],
      {:flow_failed, %{execution_id: context[:execution_id], error: error_msg}}
    )

    :ok
  end

  @impl true
  @spec get_process_context() :: any()
  def get_process_context do
    Process.get(:otel_ctx)
  end

  @impl true
  @spec set_process_context(any()) :: :ok
  def set_process_context(otel_ctx) do
    Process.put(:otel_ctx, otel_ctx)
    :ok
  end

  @impl true
  @spec event(Reactor.Middleware.step_event(), Reactor.Step.t(), Reactor.context()) :: :ok
  def event({:run_start, _arguments}, step, context) do
    handle_node_start(context, step)
    :ok
  end

  def event({:run_complete, result}, step, context) do
    handle_node_complete(context, step, result)
    :ok
  end

  def event({:run_error, errors}, step, context) do
    handle_node_error(context, step, errors)
    :ok
  end

  def event(_event, _step, _context), do: :ok

  # ── Execution-level ──────────────────────────────────────────

  defp mark_running(nil), do: :ok

  defp mark_running(execution_id) do
    case FlowExecutions.get_execution(execution_id) do
      nil -> :ok
      execution -> FlowExecutions.update_execution_status(execution, "running")
    end
  end

  # ── Node-level persistence ───────────────────────────────────

  defp handle_node_start(context, step) do
    with node_info when not is_nil(node_info) <- resolve_node(context, step) do
      FlowExecutions.create_node_execution(%{
        flow_execution_id: context.execution_id,
        node_id: node_info.id,
        node_type: Atom.to_string(node_info.type),
        status: "running",
        started_at: DateTime.utc_now()
      })

      broadcast(
        context.execution_id,
        {:node_started, %{node_id: node_info.id, node_type: node_info.type}}
      )
    end
  end

  defp handle_node_complete(context, step, result) do
    with node_info when not is_nil(node_info) <- resolve_node(context, step) do
      complete_node_record(context.execution_id, node_info.id, result)
      maybe_update_shared_state(context.execution_id, result)
      broadcast(context.execution_id, {:node_completed, %{node_id: node_info.id, result: result}})
    end
  end

  defp handle_node_error(context, step, errors) do
    with node_info when not is_nil(node_info) <- resolve_node(context, step) do
      fail_node_record(context.execution_id, node_info.id, errors)

      broadcast(
        context.execution_id,
        {:node_failed, %{node_id: node_info.id, error: format_errors(errors)}}
      )
    end
  end

  defp resolve_node(%{execution_id: eid, node_map: nmap}, step)
       when not is_nil(eid) and not is_nil(nmap) do
    Map.get(nmap, step.name)
  end

  defp resolve_node(_context, _step), do: nil

  defp complete_node_record(execution_id, node_id, result) do
    case get_node_execution(execution_id, node_id) do
      nil ->
        :ok

      node_exec ->
        duration_ms = compute_duration(node_exec.started_at)
        FlowExecutions.complete_node_execution(node_exec, result, duration_ms)
    end
  end

  defp fail_node_record(execution_id, node_id, errors) do
    case get_node_execution(execution_id, node_id) do
      nil -> :ok
      node_exec -> FlowExecutions.fail_node_execution(node_exec, format_errors(errors))
    end
  end

  # ── Helpers ──────────────────────────────────────────────────

  defp get_node_execution(execution_id, node_id) do
    Blackboex.Repo.get_by(
      Blackboex.FlowExecutions.NodeExecution,
      flow_execution_id: execution_id,
      node_id: node_id
    )
  end

  # Do not merge state when the branch was skipped — the skipped branch
  # carries only the initial/propagated state and must not overwrite state
  # set by a previously-executed matching branch node.
  defp maybe_update_shared_state(_execution_id, %{output: :__branch_skipped__}), do: :ok

  defp maybe_update_shared_state(execution_id, %{state: new_state}) when is_map(new_state) do
    FlowExecutions.merge_shared_state(execution_id, new_state)
  end

  defp maybe_update_shared_state(_execution_id, _result), do: :ok

  defp compute_duration(nil), do: nil

  defp compute_duration(started_at),
    do: DateTime.diff(DateTime.utc_now(), started_at, :millisecond)

  defp broadcast(nil, _message), do: :ok

  defp broadcast(execution_id, message) do
    PubSub.broadcast(Blackboex.PubSub, "flow_execution:#{execution_id}", message)
  end

  defp format_errors(errors) when is_list(errors) do
    errors |> Enum.map(&format_single_error/1) |> Enum.join("; ")
  end

  defp format_errors(error), do: format_single_error(error)

  defp format_single_error(%{message: msg}), do: msg
  defp format_single_error(error) when is_binary(error), do: error
  defp format_single_error(error), do: inspect(error)
end
