defmodule Blackboex.FlowSecrets.FlowSecretQueries do
  @moduledoc """
  Composable query builders for the FlowSecret schema.
  """

  import Ecto.Query, warn: false

  alias Blackboex.FlowSecrets.FlowSecret

  @spec list_for_org(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_org(organization_id) do
    FlowSecret
    |> where([s], s.organization_id == ^organization_id)
    |> order_by([s], asc: s.name)
  end

  @spec by_org_and_name(Ecto.UUID.t(), String.t()) :: Ecto.Query.t()
  def by_org_and_name(organization_id, name) do
    FlowSecret
    |> where([s], s.organization_id == ^organization_id and s.name == ^name)
  end

  @spec list_for_project(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_project(project_id) do
    FlowSecret
    |> where([s], s.project_id == ^project_id)
    |> order_by([s], asc: s.name)
  end
end
