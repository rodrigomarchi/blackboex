defmodule Blackboex.Pages do
  @moduledoc """
  The Pages context. Manages free-form Markdown pages within projects
  for planning, documentation, and notes.
  """

  alias Blackboex.Pages.Page
  alias Blackboex.Pages.PageQueries
  alias Blackboex.Repo

  # ── Page CRUD ──────────────────────────────────────────────

  @spec create_page(map()) :: {:ok, Page.t()} | {:error, Ecto.Changeset.t()}
  def create_page(attrs) do
    %Page{}
    |> Page.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_pages(Ecto.UUID.t()) :: [Page.t()]
  def list_pages(project_id) do
    project_id |> PageQueries.list_for_project() |> Repo.all()
  end

  @spec list_pages(Ecto.UUID.t(), keyword()) :: [Page.t()]
  def list_pages(project_id, opts) do
    query = PageQueries.list_for_project(project_id)

    query =
      case Keyword.get(opts, :search) do
        nil -> query
        "" -> query
        term -> PageQueries.search(query, term)
      end

    Repo.all(query)
  end

  @spec get_page(Ecto.UUID.t(), Ecto.UUID.t()) :: Page.t() | nil
  def get_page(project_id, page_id) do
    project_id |> PageQueries.by_project_and_id(page_id) |> Repo.one()
  end

  @spec get_page_by_slug(Ecto.UUID.t(), String.t()) :: Page.t() | nil
  def get_page_by_slug(project_id, slug) do
    project_id |> PageQueries.by_project_and_slug(slug) |> Repo.one()
  end

  @spec update_page(Page.t(), map()) :: {:ok, Page.t()} | {:error, Ecto.Changeset.t()}
  def update_page(%Page{} = page, attrs) do
    page
    |> Page.update_changeset(attrs)
    |> Repo.update()
  end

  @spec delete_page(Page.t()) :: {:ok, Page.t()} | {:error, Ecto.Changeset.t()}
  def delete_page(%Page{} = page) do
    Repo.delete(page)
  end

  @spec change_page(Page.t(), map()) :: Ecto.Changeset.t()
  def change_page(%Page{} = page, attrs \\ %{}) do
    Page.changeset(page, attrs)
  end
end
