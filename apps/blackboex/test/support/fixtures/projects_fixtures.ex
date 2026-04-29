defmodule Blackboex.ProjectsFixtures do
  @moduledoc """
  Test helpers for creating project entities.
  """

  alias Blackboex.Projects

  @doc """
  Creates a project for the given org and user.

  If no org/user provided, creates them via org_fixture/user_fixture.

  Returns the project struct.
  """
  @spec project_fixture(map()) :: Blackboex.Projects.Project.t()
  def project_fixture(attrs \\ %{}) do
    user = attrs[:user] || Blackboex.AccountsFixtures.user_fixture()
    org = attrs[:org] || Blackboex.OrganizationsFixtures.org_fixture(%{user: user})
    uid = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    {:ok, %{project: project}} =
      Projects.create_project(org, user, %{
        name: attrs[:name] || "Test Project #{uid}"
      })

    project
  end

  @doc """
  Creates a project membership for an existing project and user.
  """
  @spec project_membership_fixture(map()) :: Blackboex.Projects.ProjectMembership.t()
  def project_membership_fixture(attrs \\ %{}) do
    project = attrs[:project] || project_fixture()
    user = attrs[:user] || Blackboex.AccountsFixtures.user_fixture()
    role = attrs[:role] || :viewer

    {:ok, membership} = Projects.add_project_member(project, user, role)
    membership
  end

  @doc """
  Named setup: creates a project for existing user + org in context.

  Usage: `setup [:register_and_log_in_user, :create_org_and_api, :create_project]`
  """
  @spec create_project(map()) :: map()
  def create_project(%{user: user, org: org}) do
    {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Test Project"})
    %{project: project}
  end

  def create_project(%{user: user}) do
    org = Blackboex.OrganizationsFixtures.org_fixture(%{user: user})
    {:ok, %{project: project}} = Projects.create_project(org, user, %{name: "Test Project"})
    %{org: org, project: project}
  end
end
