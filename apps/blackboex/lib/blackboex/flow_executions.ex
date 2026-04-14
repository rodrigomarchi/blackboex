defmodule Blackboex.FlowExecutions do
  @moduledoc """
  The FlowExecutions context. Manages execution records for flows and their nodes.
  """

  import Ecto.Query, warn: false

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
      project_id: flow.project_id,
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

  @spec halt_execution(FlowExecution.t(), String.t()) ::
          {:ok, FlowExecution.t()} | {:error, Ecto.Changeset.t()}
  def halt_execution(%FlowExecution{} = execution, event_type) do
    execution
    |> FlowExecution.changeset(%{status: "halted", wait_event_type: event_type})
    |> Repo.update()
  end

  @spec get_halted_execution_by_token(String.t(), String.t()) :: FlowExecution.t() | nil
  def get_halted_execution_by_token(token, event_type) do
    from(e in FlowExecution,
      join: f in assoc(e, :flow),
      where: f.webhook_token == ^token,
      where: e.status == "halted",
      where: e.wait_event_type == ^event_type,
      order_by: [desc: e.inserted_at],
      limit: 1,
      preload: [:flow]
    )
    |> Repo.one()
  end

  @spec merge_shared_state(Ecto.UUID.t(), map()) :: :ok | {:error, any()}
  def merge_shared_state(execution_id, new_state) when is_map(new_state) do
    from(e in FlowExecution,
      where: e.id == ^execution_id,
      update: [
        set: [
          shared_state:
            fragment("COALESCE(shared_state, '{}'::jsonb) || ?::jsonb", type(^new_state, :map))
        ]
      ]
    )
    |> Repo.update_all([])

    :ok
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

  @spec skip_node_execution(NodeExecution.t(), integer()) ::
          {:ok, NodeExecution.t()} | {:error, Ecto.Changeset.t()}
  def skip_node_execution(%NodeExecution{} = node_exec, duration_ms) do
    node_exec
    |> NodeExecution.changeset(%{
      status: "skipped",
      output: nil,
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
