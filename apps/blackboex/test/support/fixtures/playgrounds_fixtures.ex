defmodule Blackboex.PlaygroundsFixtures do
  @moduledoc """
  Test helpers for creating Playground entities.
  """

  alias Blackboex.Playgrounds

  @doc """
  Creates a playground for the given user and organization.

  ## Options

    * `:user` - the owner user (required, or auto-created with org)
    * `:org` - the organization (required, or auto-created with user)
    * `:project` - the project (default: org's default project)
    * `:name` - playground name (default: auto-generated)
    * Any additional attrs are passed through to `Playgrounds.create_playground/1`

  Returns the Playground struct.
  """
  @spec playground_fixture(map()) :: Blackboex.Playgrounds.Playground.t()
  def playground_fixture(attrs \\ %{}) do
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

    known_keys = [:user, :org, :project, :name]
    extra = Map.drop(attrs, known_keys)

    {:ok, playground} =
      Playgrounds.create_playground(
        Map.merge(
          %{
            name: attrs[:name] || "Test Playground #{System.unique_integer([:positive])}",
            organization_id: org.id,
            project_id: project.id,
            user_id: user.id
          },
          extra
        )
      )

    playground
  end

  @doc """
  Named setup: creates a playground for existing user + org in context.

  Requires `:user` and `:org` in context.

  Usage: `setup [:register_and_log_in_user, :create_org, :create_playground]`
  """
  @spec create_playground(map()) :: map()
  def create_playground(%{user: user, org: org} = context) do
    project = context[:project]
    playground = playground_fixture(%{user: user, org: org, project: project})
    %{playground: playground}
  end
end
