defmodule Blackboex.FlowExecutions do
  @moduledoc """
  The FlowExecutions context. Manages execution records for flows and their nodes.
  """

  alias Blackboex.FlowExecutions.FlowExecution
  alias Blackboex.FlowExecutions.FlowExecutionQueries
  alias Blackboex.FlowExecutions.NodeExecution
  alias Blackboex.Repo

  # ── FlowExecution ─────────────────────────────────────────

  @spec create_execution(Blackboex.Flows.Flow.t(), map()) ::
          {:ok, FlowExecution.t()} | {:error, Ecto.Changeset.t()}
  def create_execution(flow, input \\ %{}) do
    %FlowExecution{}
    |> FlowExecution.changeset(%{
      flow_id: flow.id,
      organization_id: flow.organization_id,
      input: input,
      status: "pending"
    })
    |> Repo.insert()
  end

  @spec get_execution(Ecto.UUID.t()) :: FlowExecution.t() | nil
  def get_execution(id) do
    id
    |> FlowExecutionQueries.by_id()
    |> FlowExecutionQueries.with_node_executions()
    |> Repo.one()
  end

  @spec get_execution_for_org(Ecto.UUID.t(), Ecto.UUID.t()) :: FlowExecution.t() | nil
  def get_execution_for_org(org_id, id) do
    org_id
    |> FlowExecutionQueries.by_org_and_id(id)
    |> FlowExecutionQueries.with_node_executions()
    |> Repo.one()
  end

  @spec list_executions_for_flow(Ecto.UUID.t()) :: [FlowExecution.t()]
  def list_executions_for_flow(flow_id) do
    flow_id |> FlowExecutionQueries.list_for_flow() |> Repo.all()
  end

  @spec update_execution_status(FlowExecution.t(), String.t()) ::
          {:ok, FlowExecution.t()} | {:error, Ecto.Changeset.t()}
  def update_execution_status(%FlowExecution{} = execution, status) do
    attrs =
      case status do
        "running" -> %{status: status, started_at: DateTime.utc_now()}
        _ -> %{status: status}
      end

    execution
    |> FlowExecution.changeset(attrs)
    |> Repo.update()
  end

  @spec complete_execution(FlowExecution.t(), map(), integer()) ::
          {:ok, FlowExecution.t()} | {:error, Ecto.Changeset.t()}
  def complete_execution(%FlowExecution{} = execution, output, duration_ms) do
    execution
    |> FlowExecution.changeset(%{
      status: "completed",
      output: output,
      finished_at: DateTime.utc_now(),
      duration_ms: duration_ms
    })
    |> Repo.update()
  end

  @spec fail_execution(FlowExecution.t(), String.t()) ::
          {:ok, FlowExecution.t()} | {:error, Ecto.Changeset.t()}
  def fail_execution(%FlowExecution{} = execution, error) do
    execution
    |> FlowExecution.changeset(%{
      status: "failed",
      error: error,
      finished_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  # ── NodeExecution ─────────────────────────────────────────

  @spec create_node_execution(map()) ::
          {:ok, NodeExecution.t()} | {:error, Ecto.Changeset.t()}
  def create_node_execution(attrs) do
    %NodeExecution{}
    |> NodeExecution.changeset(attrs)
    |> Repo.insert()
  end

  @spec complete_node_execution(NodeExecution.t(), map(), integer()) ::
          {:ok, NodeExecution.t()} | {:error, Ecto.Changeset.t()}
  def complete_node_execution(%NodeExecution{} = node_exec, output, duration_ms) do
    node_exec
    |> NodeExecution.changeset(%{
      status: "completed",
      output: output,
      finished_at: DateTime.utc_now(),
      duration_ms: duration_ms
    })
    |> Repo.update()
  end

  @spec fail_node_execution(NodeExecution.t(), String.t()) ::
          {:ok, NodeExecution.t()} | {:error, Ecto.Changeset.t()}
  def fail_node_execution(%NodeExecution{} = node_exec, error) do
    node_exec
    |> NodeExecution.changeset(%{
      status: "failed",
      error: error,
      finished_at: DateTime.utc_now()
    })
    |> Repo.update()
  end
end
