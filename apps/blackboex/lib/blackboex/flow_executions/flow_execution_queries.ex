defmodule Blackboex.FlowExecutions.FlowExecutionQueries do
  @moduledoc """
  Composable query builders for the FlowExecution schema.
  """

  import Ecto.Query, warn: false

  alias Blackboex.FlowExecutions.FlowExecution

  @spec list_for_flow(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_flow(flow_id) do
    FlowExecution
    |> where([e], e.flow_id == ^flow_id)
    |> order_by([e], desc: e.inserted_at)
  end

  @spec by_id(Ecto.UUID.t()) :: Ecto.Query.t()
  def by_id(id) do
    FlowExecution
    |> where([e], e.id == ^id)
  end

  @spec by_org_and_id(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_org_and_id(org_id, id) do
    FlowExecution
    |> where([e], e.id == ^id and e.organization_id == ^org_id)
  end

  @spec with_node_executions(Ecto.Query.t()) :: Ecto.Query.t()
  def with_node_executions(query) do
    preload(query, :node_executions)
  end
end
