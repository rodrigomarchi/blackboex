defmodule Blackboex.Apis.ApiQueries do
  @moduledoc """
  Composable query builders for the Api schema.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.Api

  @spec list_for_org(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_org(organization_id) do
    Api
    |> where([a], a.organization_id == ^organization_id)
    |> without_samples()
    |> order_by([a], desc: a.inserted_at)
  end

  @spec without_samples(Ecto.Queryable.t()) :: Ecto.Query.t()
  def without_samples(query) do
    where(query, [a], is_nil(a.sample_uuid))
  end

  @spec by_org_and_id(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_org_and_id(organization_id, api_id) do
    Api
    |> where([a], a.organization_id == ^organization_id and a.id == ^api_id)
  end

  @spec list_for_project(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_project(project_id) do
    Api
    |> where([a], a.project_id == ^project_id)
    |> order_by([a], desc: a.inserted_at)
  end

  @doc """
  Returns apis for a project ordered by name ASC, with an optional `:limit` (default 50).
  """
  @spec list_for_project_sorted(Ecto.UUID.t(), keyword()) :: Ecto.Query.t()
  def list_for_project_sorted(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Api
    |> where([a], a.project_id == ^project_id)
    |> order_by([a], asc: a.name)
    |> limit(^limit)
  end

  @spec by_project_and_slug(Ecto.UUID.t(), String.t()) :: Ecto.Query.t()
  def by_project_and_slug(project_id, slug) do
    Api
    |> where([a], a.project_id == ^project_id and a.slug == ^slug)
  end

  @spec by_org_and_id_only(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_org_and_id_only(org_id, api_id) do
    Api
    |> where([a], a.organization_id == ^org_id and a.id == ^api_id)
  end
end
