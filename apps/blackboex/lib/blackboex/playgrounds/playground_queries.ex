defmodule Blackboex.Playgrounds.PlaygroundQueries do
  @moduledoc """
  Composable query builders for the Playground schema.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Playgrounds.Playground

  @spec list_for_project(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_project(project_id) do
    Playground
    |> where([p], p.project_id == ^project_id)
    |> order_by([p], desc: p.updated_at)
  end

  @doc """
  Returns playgrounds for a project ordered by name ASC, with an optional `:limit` (default 50).
  """
  @spec list_for_project_sorted(Ecto.UUID.t(), keyword()) :: Ecto.Query.t()
  def list_for_project_sorted(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Playground
    |> where([p], p.project_id == ^project_id)
    |> order_by([p], asc: p.name)
    |> limit(^limit)
  end

  @spec list_for_org(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_org(organization_id) do
    Playground
    |> where([p], p.organization_id == ^organization_id)
    |> order_by([p], desc: p.updated_at)
  end

  @spec by_project_and_id(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_project_and_id(project_id, playground_id) do
    Playground
    |> where([p], p.project_id == ^project_id and p.id == ^playground_id)
  end

  @spec by_org_and_id(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_org_and_id(org_id, playground_id) do
    Playground
    |> where([p], p.organization_id == ^org_id and p.id == ^playground_id)
  end

  @spec by_project_and_slug(Ecto.UUID.t(), String.t()) :: Ecto.Query.t()
  def by_project_and_slug(project_id, slug) do
    Playground
    |> where([p], p.project_id == ^project_id and p.slug == ^slug)
  end

  @spec search(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def search(query, term) do
    like = "%#{sanitize_like(term)}%"
    where(query, [p], ilike(p.name, ^like) or ilike(p.description, ^like))
  end

  defp sanitize_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
