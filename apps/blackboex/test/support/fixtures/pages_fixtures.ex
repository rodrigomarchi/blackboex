defmodule Blackboex.PagesFixtures do
  @moduledoc """
  Test helpers for creating Page entities.
  """

  alias Blackboex.Pages

  @doc """
  Creates a page for the given user and organization.

  ## Options

    * `:user` - the owner user (required, or auto-created with org)
    * `:org` - the organization (required, or auto-created with user)
    * `:project` - the project (default: org's default project)
    * `:title` - page title (default: auto-generated)
    * Any additional attrs are passed through to `Pages.create_page/1`

  Returns the Page struct.
  """
  @spec page_fixture(map()) :: Blackboex.Pages.Page.t()
  def page_fixture(attrs \\ %{}) do
    {user, org} =
      case {attrs[:user], attrs[:org]} do
        {nil, nil} ->
          Blackboex.OrganizationsFixtures.user_and_org_fixture()

        {user, nil} ->
          {user, Blackboex.OrganizationsFixtures.org_fixture(%{user: user})}

        {nil, org} ->
          {Blackboex.AccountsFixtures.user_fixture(), org}

        {user, org} ->
          {user, org}
      end

    project =
      attrs[:project] || Blackboex.Projects.get_default_project(org.id) ||
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org})

    known_keys = [:user, :org, :project, :title]
    extra = Map.drop(attrs, known_keys)

    {:ok, page} =
      Pages.create_page(
        Map.merge(
          %{
            title: attrs[:title] || "Test Page #{System.unique_integer([:positive])}",
            organization_id: org.id,
            project_id: project.id,
            user_id: user.id
          },
          extra
        )
      )

    page
  end

  @doc """
  Named setup: creates a page for existing user + org in context.

  Requires `:user` and `:org` in context.

  Usage: `setup [:register_and_log_in_user, :create_org, :create_page]`
  """
  @spec create_page(map()) :: map()
  def create_page(%{user: user, org: org} = context) do
    project = context[:project]
    page = page_fixture(%{user: user, org: org, project: project})
    %{page: page}
  end
end
