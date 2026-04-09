defmodule Blackboex.Workers.FlowExecutionWorker do
  @moduledoc """
  Oban worker for async flow execution.
  Loads the FlowExecution record and flow, then runs the executor.
  """

  use Oban.Worker, queue: :flows, max_attempts: 3

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.Flows

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, any()}
  def perform(%Oban.Job{args: %{"execution_id" => execution_id, "flow_id" => flow_id}}) do
    with {:execution, execution} when not is_nil(execution) <-
           {:execution, FlowExecutions.get_execution(execution_id)},
         {:flow, flow} when not is_nil(flow) <-
           {:flow, Blackboex.Repo.get(Flows.Flow, flow_id)} do
      # Skip if already completed/failed (idempotent on retry)
      if execution.status in ["completed", "failed"] do
        :ok
      else
        execute(flow, execution)
      end
    else
      {:execution, nil} ->
        Logger.error("FlowExecutionWorker: execution #{execution_id} not found")
        {:error, "execution not found"}

      {:flow, nil} ->
        execution = FlowExecutions.get_execution(execution_id)
        if execution, do: FlowExecutions.fail_execution(execution, "flow not found")
        {:error, "flow not found"}
    end
  end

  defp execute(flow, execution) do
    case FlowExecutor.run(flow, execution.input, execution.id) do
      {:ok, result} ->
        # Reload to get started_at set by middleware
        # Extract output from EndNode result (%{output: X, state: Y})
        output = extract_output(result)
        execution = FlowExecutions.get_execution(execution.id)
        duration_ms = compute_duration(execution)
        FlowExecutions.complete_execution(execution, wrap_for_db(output), duration_ms)
        :ok

      {:error, reason} ->
        error_msg = if is_binary(reason), do: reason, else: inspect(reason)
        execution = FlowExecutions.get_execution(execution.id)
        FlowExecutions.fail_execution(execution, error_msg)
        {:error, error_msg}
    end
  end

  defp extract_output(%{output: output}), do: output
  defp extract_output(result), do: result

  defp wrap_for_db(output) when is_map(output), do: output
  defp wrap_for_db(output), do: %{"value" => output}

  defp compute_duration(%{started_at: %DateTime{} = started}) do
    DateTime.diff(DateTime.utc_now(), started, :millisecond)
  end

  defp compute_duration(%{inserted_at: %NaiveDateTime{} = inserted}) do
    NaiveDateTime.diff(DateTime.to_naive(DateTime.utc_now()), inserted, :millisecond)
  end

  defp compute_duration(_), do: 0
end
