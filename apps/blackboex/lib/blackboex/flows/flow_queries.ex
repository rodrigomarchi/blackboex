defmodule Blackboex.Flows.FlowQueries do
  @moduledoc """
  Composable query builders for the Flow schema.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Flows.Flow

  @spec list_for_org(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_org(organization_id) do
    Flow
    |> where([f], f.organization_id == ^organization_id)
    |> order_by([f], desc: f.inserted_at)
  end

  @spec by_org_and_id(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_org_and_id(organization_id, flow_id) do
    Flow
    |> where([f], f.organization_id == ^organization_id and f.id == ^flow_id)
  end

  @spec by_org_and_slug(Ecto.UUID.t(), String.t()) :: Ecto.Query.t()
  def by_org_and_slug(organization_id, slug) do
    Flow
    |> where([f], f.organization_id == ^organization_id and f.slug == ^slug)
  end

  @spec search(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def search(query, term) do
    like = "%#{term}%"
    where(query, [f], ilike(f.name, ^like) or ilike(f.description, ^like))
  end

  @spec list_for_project(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_project(project_id) do
    Flow
    |> where([f], f.project_id == ^project_id)
    |> order_by([f], desc: f.inserted_at)
  end

  @spec by_project_and_slug(Ecto.UUID.t(), String.t()) :: Ecto.Query.t()
  def by_project_and_slug(project_id, slug) do
    Flow
    |> where([f], f.project_id == ^project_id and f.slug == ^slug)
  end
end
