defmodule BlackboexWeb.FlowExecutionJSON do
  @moduledoc """
  JSON rendering for flow executions.
  """

  alias Blackboex.FlowExecutions.FlowExecution
  alias Blackboex.FlowExecutions.NodeExecution

  @spec index([FlowExecution.t()]) :: map()
  def index(executions) do
    %{data: Enum.map(executions, &execution_summary/1)}
  end

  @spec show(FlowExecution.t()) :: map()
  def show(execution) do
    %{data: execution_detail(execution)}
  end

  defp execution_summary(%FlowExecution{} = exec) do
    %{
      id: exec.id,
      flow_id: exec.flow_id,
      status: exec.status,
      duration_ms: exec.duration_ms,
      inserted_at: exec.inserted_at,
      finished_at: exec.finished_at
    }
  end

  defp execution_detail(%FlowExecution{} = exec) do
    %{
      id: exec.id,
      flow_id: exec.flow_id,
      status: exec.status,
      input: exec.input,
      output: exec.output,
      error: exec.error,
      duration_ms: exec.duration_ms,
      inserted_at: exec.inserted_at,
      started_at: exec.started_at,
      finished_at: exec.finished_at,
      node_executions: render_node_executions(exec)
    }
  end

  defp render_node_executions(%{node_executions: %Ecto.Association.NotLoaded{}}), do: []

  defp render_node_executions(%{node_executions: nodes}) do
    Enum.map(nodes, &node_execution/1)
  end

  defp node_execution(%NodeExecution{} = ne) do
    %{
      id: ne.id,
      node_id: ne.node_id,
      node_type: ne.node_type,
      status: ne.status,
      input: ne.input,
      output: ne.output,
      error: ne.error,
      duration_ms: ne.duration_ms,
      started_at: ne.started_at,
      finished_at: ne.finished_at
    }
  end
end
