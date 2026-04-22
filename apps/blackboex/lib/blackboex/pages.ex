defmodule Blackboex.Pages do
  @moduledoc """
  The Pages context. Manages free-form Markdown pages within projects
  for planning, documentation, and notes.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Pages.Page
  alias Blackboex.Pages.PageQueries
  alias Blackboex.Repo

  @max_depth 5

  # ── Page CRUD ──────────────────────────────────────────────

  @spec create_page(map()) ::
          {:ok, Page.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def create_page(attrs) do
    org_id = attrs[:organization_id] || attrs["organization_id"]
    project_id = attrs[:project_id] || attrs["project_id"]

    with :ok <- ensure_project_in_org(project_id, org_id) do
      attrs = auto_assign_position(attrs)

      %Page{}
      |> Page.changeset(attrs)
      |> Repo.insert()
    end
  end

  @spec list_root_pages_for_project(Ecto.UUID.t(), keyword()) :: [Page.t()]
  def list_root_pages_for_project(project_id, opts \\ []) do
    project_id |> PageQueries.root_pages_for_project(opts) |> Repo.all()
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

  @doc """
  Fetches a Page by organization_id and page_id. Returns `nil` when not found or
  the page does not belong to the given organization.
  """
  @spec get_for_org(Ecto.UUID.t(), Ecto.UUID.t()) :: Page.t() | nil
  def get_for_org(org_id, page_id) do
    org_id |> PageQueries.by_org_and_id(page_id) |> Repo.one()
  end

  @spec update_page(Page.t(), map()) :: {:ok, Page.t()} | {:error, Ecto.Changeset.t()}
  def update_page(%Page{} = page, attrs) do
    page
    |> Page.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Applies an AI-generated edit to a Page's content. Validates that the page
  belongs to the scope's organization (defense-in-depth IDOR check; the
  agent layer also gates this upstream). Updates only `:content`.
  """
  @spec record_ai_edit(Page.t(), String.t(), map()) ::
          {:ok, Page.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def record_ai_edit(%Page{} = page, new_content, %{organization: %{id: org_id}})
      when is_binary(new_content) do
    if page.organization_id == org_id do
      update_page(page, %{content: new_content})
    else
      {:error, :unauthorized}
    end
  end

  @spec delete_page(Page.t()) :: {:ok, Page.t()} | {:error, Ecto.Changeset.t()}
  def delete_page(%Page{} = page) do
    Repo.delete(page)
  end

  @spec change_page(Page.t(), map()) :: Ecto.Changeset.t()
  def change_page(%Page{} = page, attrs \\ %{}) do
    Page.changeset(page, attrs)
  end

  # ── Tree ───────────────────────────────────────────────────

  @doc """
  Returns a nested tree of pages for a project.

  Each node is `%{page: %Page{}, children: [%{page: ..., children: ...}]}`.
  """
  @spec list_page_tree(Ecto.UUID.t()) :: [map()]
  def list_page_tree(project_id) do
    pages = project_id |> PageQueries.tree_for_project() |> Repo.all()
    build_tree(pages)
  end

  @doc """
  Moves a page to a new parent at the given position.

  Validates depth limit (max #{@max_depth}), self-parenting, and circular references.
  """
  @spec move_page(Page.t(), Ecto.UUID.t() | nil, non_neg_integer()) ::
          {:ok, Page.t()} | {:error, atom()}
  def move_page(%Page{} = page, new_parent_id, position) do
    cond do
      new_parent_id == page.id ->
        {:error, :self_parent}

      new_parent_id && descendant?(new_parent_id, page.id) ->
        {:error, :circular_reference}

      new_parent_id && exceeds_depth?(page, new_parent_id) ->
        {:error, :max_depth_exceeded}

      true ->
        page
        |> Page.update_changeset(%{parent_id: new_parent_id, position: position})
        |> Repo.update()
    end
  end

  # ── Private ────────────────────────────────────────────────

  defp ensure_project_in_org(nil, _org_id), do: :ok
  defp ensure_project_in_org(_project_id, nil), do: :ok

  defp ensure_project_in_org(project_id, org_id) do
    query =
      from p in Blackboex.Projects.Project,
        where: p.id == ^project_id and p.organization_id == ^org_id,
        select: 1

    if Repo.exists?(query), do: :ok, else: {:error, :forbidden}
  end

  defp auto_assign_position(attrs) do
    cond do
      Map.has_key?(attrs, :position) || Map.has_key?(attrs, "position") ->
        attrs

      attrs[:project_id] || attrs["project_id"] ->
        compute_next_position(attrs)

      true ->
        attrs
    end
  end

  defp compute_next_position(attrs) do
    project_id = attrs[:project_id] || attrs["project_id"]
    parent_id = attrs[:parent_id] || attrs["parent_id"]
    max_pos = project_id |> PageQueries.max_position(parent_id) |> Repo.one()
    next_pos = if max_pos, do: max_pos + 1, else: 0

    key = if Map.has_key?(attrs, :project_id), do: :position, else: "position"
    Map.put(attrs, key, next_pos)
  end

  defp build_tree(pages) do
    by_parent = Enum.group_by(pages, & &1.parent_id)

    build_children(by_parent, nil)
  end

  defp build_children(by_parent, parent_id) do
    by_parent
    |> Map.get(parent_id, [])
    |> Enum.map(fn page ->
      %{page: page, children: build_children(by_parent, page.id)}
    end)
  end

  defp descendant?(potential_descendant_id, ancestor_id) do
    ancestor_ids = walk_ancestors(potential_descendant_id)
    ancestor_id in ancestor_ids
  end

  defp exceeds_depth?(%Page{} = page, new_parent_id) do
    # Depth of new parent from root: ancestors count + 1 (parent itself)
    parent_depth = length(walk_ancestors(new_parent_id)) + 1

    # Max depth of page's subtree (includes page itself)
    subtree_depth = 1 + max_subtree_depth(page)

    # Total depth of the deepest path through this move
    parent_depth + subtree_depth > @max_depth
  end

  defp walk_ancestors(page_id, acc \\ []) do
    case PageQueries.parent_lookup(page_id) |> Repo.one() do
      nil -> acc
      {_id, nil} -> acc
      {_id, parent_id} -> walk_ancestors(parent_id, [parent_id | acc])
    end
  end

  defp max_subtree_depth(%Page{} = page) do
    children =
      page.id
      |> PageQueries.children_of()
      |> Repo.all()

    case children do
      [] -> 0
      kids -> 1 + (kids |> Enum.map(&max_subtree_depth/1) |> Enum.max())
    end
  end
end
