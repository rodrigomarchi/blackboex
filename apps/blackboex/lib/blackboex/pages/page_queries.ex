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

  @doc """
  Returns root pages (parent_id IS NULL) for a project, ordered by title ASC.
  Accepts `:limit` keyword option (default 100).
  """
  @spec root_pages_for_project(Ecto.UUID.t(), keyword()) :: Ecto.Query.t()
  def root_pages_for_project(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Page
    |> where([p], p.project_id == ^project_id and is_nil(p.parent_id))
    |> order_by([p], asc: p.title)
    |> limit(^limit)
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

  @spec by_org_and_id(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_org_and_id(org_id, page_id) do
    Page
    |> where([p], p.organization_id == ^org_id and p.id == ^page_id)
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

  @spec tree_for_project(Ecto.UUID.t()) :: Ecto.Query.t()
  def tree_for_project(project_id) do
    Page
    |> where([p], p.project_id == ^project_id)
    |> order_by([p], asc: p.position, asc: p.inserted_at)
  end

  @spec children_of(Ecto.UUID.t()) :: Ecto.Query.t()
  def children_of(parent_id) do
    Page
    |> where([p], p.parent_id == ^parent_id)
    |> order_by([p], asc: p.position)
  end

  @spec max_position(Ecto.UUID.t(), Ecto.UUID.t() | nil) :: Ecto.Query.t()
  def max_position(project_id, nil) do
    Page
    |> where([p], p.project_id == ^project_id and is_nil(p.parent_id))
    |> select([p], max(p.position))
  end

  def max_position(project_id, parent_id) do
    Page
    |> where([p], p.project_id == ^project_id and p.parent_id == ^parent_id)
    |> select([p], max(p.position))
  end

  @doc """
  Returns a single page by id, selecting only id and parent_id.
  Used for walking the ancestor chain iteratively.
  """
  @spec parent_lookup(Ecto.UUID.t()) :: Ecto.Query.t()
  def parent_lookup(page_id) do
    Page
    |> where([p], p.id == ^page_id)
    |> select([p], {p.id, p.parent_id})
  end

  defp sanitize_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
