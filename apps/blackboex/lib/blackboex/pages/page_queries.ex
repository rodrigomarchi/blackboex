defmodule Blackboex.Pages.PageQueries do
  @moduledoc """
  Composable query builders for the Page schema.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Pages.Page

  @spec list_for_project(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_project(project_id) do
    Page
    |> where([p], p.project_id == ^project_id)
    |> order_by([p], desc: p.updated_at)
  end

  @spec list_for_org(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_org(organization_id) do
    Page
    |> where([p], p.organization_id == ^organization_id)
    |> order_by([p], desc: p.updated_at)
  end

  @spec by_project_and_id(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_project_and_id(project_id, page_id) do
    Page
    |> where([p], p.project_id == ^project_id and p.id == ^page_id)
  end

  @spec by_project_and_slug(Ecto.UUID.t(), String.t()) :: Ecto.Query.t()
  def by_project_and_slug(project_id, slug) do
    Page
    |> where([p], p.project_id == ^project_id and p.slug == ^slug)
  end

  @spec search(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def search(query, term) do
    like = "%#{sanitize_like(term)}%"
    where(query, [p], ilike(p.title, ^like) or ilike(p.content, ^like))
  end

  defp sanitize_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
