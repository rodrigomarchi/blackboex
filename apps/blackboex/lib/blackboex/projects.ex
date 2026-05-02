defmodule Blackboex.Projects do
  @moduledoc """
  The Projects context. Manages projects and project memberships within organizations.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Organizations.Membership
  alias Blackboex.Projects.{Project, ProjectMembership, ProjectQueries}
  alias Blackboex.Repo
  alias Ecto.Multi

  defdelegate provision_sample_workspace(organization, user),
    to: Blackboex.Projects.Samples,
    as: :provision_for_org

  defdelegate sync_sample_workspace(project, user \\ nil), to: Blackboex.Projects.Samples
  defdelegate sync_all_sample_workspaces(opts \\ []), to: Blackboex.Projects.Samples

  defdelegate dry_run_sample_workspace_sync(opts \\ []),
    to: Blackboex.Projects.Samples,
    as: :dry_run

  @spec create_project(
          Blackboex.Organizations.Organization.t(),
          Blackboex.Accounts.User.t(),
          map()
        ) ::
          {:ok, %{project: Project.t(), membership: ProjectMembership.t()}}
          | {:error, atom(), any(), map()}
  def create_project(organization, user, attrs) do
    attrs = Map.put(attrs, :organization_id, organization.id)

    Multi.new()
    |> Multi.insert(:project, Project.changeset(%Project{}, attrs))
    |> Multi.insert(:membership, fn %{project: project} ->
      ProjectMembership.changeset(%ProjectMembership{}, %{
        project_id: project.id,
        user_id: user.id,
        role: :admin
      })
    end)
    |> Repo.transaction()
  end

  @spec create_default_project(
          Blackboex.Organizations.Organization.t(),
          Blackboex.Accounts.User.t()
        ) ::
          {:ok, %{project: Project.t(), membership: ProjectMembership.t()}}
          | {:error, atom(), any(), map()}
  def create_default_project(organization, user) do
    create_project(organization, user, %{name: "Default"})
  end

  @spec list_projects_with_counts(Blackboex.Organizations.Organization.t()) :: [map()]
  def list_projects_with_counts(org) do
    org |> ProjectQueries.list_with_counts() |> Repo.all()
  end

  @spec list_projects(Ecto.UUID.t()) :: [Project.t()]
  def list_projects(organization_id) do
    organization_id
    |> ProjectQueries.for_organization()
    |> Repo.all()
  end

  @spec count_projects_for_org(Ecto.UUID.t()) :: non_neg_integer()
  def count_projects_for_org(organization_id) do
    organization_id
    |> ProjectQueries.for_organization()
    |> Repo.aggregate(:count)
  end

  @spec list_user_projects(Ecto.UUID.t(), integer()) :: [Project.t()]
  def list_user_projects(organization_id, user_id) do
    organization_id
    |> ProjectQueries.for_user(user_id)
    |> Repo.all()
  end

  @spec get_default_project(Ecto.UUID.t()) :: Project.t() | nil
  def get_default_project(organization_id) do
    from(p in Project,
      where: p.organization_id == ^organization_id,
      order_by: [asc: p.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @spec get_project(Ecto.UUID.t(), Ecto.UUID.t()) :: Project.t() | nil
  def get_project(organization_id, project_id) do
    organization_id
    |> ProjectQueries.by_org_and_id(project_id)
    |> Repo.one()
  end

  @spec get_project_by_slug(Ecto.UUID.t(), String.t()) :: Project.t() | nil
  def get_project_by_slug(organization_id, slug) do
    organization_id
    |> ProjectQueries.by_org_and_slug(slug)
    |> Repo.one()
  end

  @spec update_project(Project.t(), map()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Repo.update()
  end

  @spec delete_project(Project.t()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @spec add_project_member(Project.t(), Blackboex.Accounts.User.t(), atom()) ::
          {:ok, ProjectMembership.t()} | {:error, Ecto.Changeset.t()}
  def add_project_member(%Project{} = project, user, role) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{
      project_id: project.id,
      user_id: user.id,
      role: role
    })
    |> Repo.insert()
  end

  @spec remove_project_member(ProjectMembership.t()) ::
          {:ok, ProjectMembership.t()} | {:error, Ecto.Changeset.t()}
  def remove_project_member(%ProjectMembership{} = membership) do
    Repo.delete(membership)
  end

  @spec update_project_member_role(ProjectMembership.t(), atom()) ::
          {:ok, ProjectMembership.t()} | {:error, Ecto.Changeset.t()}
  def update_project_member_role(%ProjectMembership{} = membership, role) do
    membership
    |> ProjectMembership.changeset(%{role: role})
    |> Repo.update()
  end

  @spec get_project_membership(Project.t(), Blackboex.Accounts.User.t()) ::
          ProjectMembership.t() | nil
  def get_project_membership(%Project{} = project, user) do
    Repo.get_by(ProjectMembership, project_id: project.id, user_id: user.id)
  end

  @spec list_eligible_members(
          Blackboex.Organizations.Organization.t(),
          Project.t()
        ) :: [Membership.t()]
  def list_eligible_members(%{id: org_id}, %Project{id: project_id}) do
    from(m in Membership,
      where: m.organization_id == ^org_id,
      where:
        m.user_id not in subquery(
          from(pm in ProjectMembership,
            where: pm.project_id == ^project_id,
            select: pm.user_id
          )
        ),
      preload: [:user]
    )
    |> Repo.all()
  end

  @spec list_project_members(Ecto.UUID.t()) :: [ProjectMembership.t()]
  def list_project_members(project_id) do
    from(pm in ProjectMembership,
      where: pm.project_id == ^project_id,
      preload: [:user]
    )
    |> Repo.all()
  end

  @spec user_has_project_access?(
          Blackboex.Organizations.Organization.t(),
          Membership.t() | nil,
          Project.t(),
          Blackboex.Accounts.User.t()
        ) :: boolean()
  def user_has_project_access?(_org, %Membership{role: role}, _project, _user)
      when role in [:owner, :admin] do
    true
  end

  def user_has_project_access?(_org, _membership, project, user) do
    case Repo.get_by(ProjectMembership, project_id: project.id, user_id: user.id) do
      nil -> false
      _ -> true
    end
  end
end
