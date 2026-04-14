defmodule Blackboex.Organizations do
  @moduledoc """
  The Organizations context. Manages organizations, memberships, and multi-tenancy.
  """

  alias Blackboex.Accounts.User
  alias Blackboex.Audit
  alias Blackboex.Organizations.{Membership, Organization, OrganizationQueries}
  alias Blackboex.Projects.{Project, ProjectMembership}
  alias Blackboex.Repo
  alias Ecto.Multi

  @spec create_organization(User.t(), map()) ::
          {:ok, %{organization: Organization.t(), membership: Membership.t()}}
          | {:error, atom(), Ecto.Changeset.t(), map()}
  def create_organization(%User{} = user, attrs) do
    Multi.new()
    |> Multi.insert(:organization, Organization.changeset(%Organization{}, attrs))
    |> Multi.insert(:membership, fn %{organization: org} ->
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        organization_id: org.id,
        role: :owner
      })
    end)
    |> Multi.insert(:project, fn %{organization: org} ->
      Project.changeset(%Project{}, %{
        name: "Default",
        organization_id: org.id
      })
    end)
    |> Multi.insert(:project_membership, fn %{project: project} ->
      ProjectMembership.changeset(
        %ProjectMembership{},
        %{
          project_id: project.id,
          user_id: user.id,
          role: :admin
        }
      )
    end)
    |> Repo.transaction()
  end

  @spec list_user_organizations(User.t()) :: [Organization.t()]
  def list_user_organizations(%User{} = user) do
    user.id
    |> OrganizationQueries.for_user()
    |> Repo.all()
  end

  @spec get_organization!(Ecto.UUID.t()) :: Organization.t()
  def get_organization!(id) do
    Repo.get!(Organization, id)
  end

  @spec get_organization(Ecto.UUID.t()) :: Organization.t() | nil
  def get_organization(id) do
    Repo.get(Organization, id)
  end

  @spec get_organization_by_slug(String.t()) :: Organization.t() | nil
  def get_organization_by_slug(slug) do
    Repo.get_by(Organization, slug: slug)
  end

  @spec update_organization(Organization.t(), map()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def update_organization(%Organization{} = org, attrs) do
    org
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  @spec add_member(Organization.t(), User.t(), atom()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def add_member(%Organization{} = org, %User{} = user, role) do
    case %Membership{}
         |> Membership.changeset(%{
           user_id: user.id,
           organization_id: org.id,
           role: role
         })
         |> Repo.insert() do
      {:ok, membership} ->
        Audit.log_async("member.added", %{
          resource_type: "membership",
          resource_id: membership.id,
          organization_id: org.id,
          user_id: user.id
        })

        {:ok, membership}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec remove_member(Organization.t(), Membership.t()) ::
          {:ok, Membership.t()} | {:error, :last_owner}
  def remove_member(%Organization{} = org, %Membership{role: :owner} = membership) do
    import Ecto.Query, warn: false

    owner_count =
      Membership
      |> where([m], m.organization_id == ^org.id and m.role == :owner)
      |> Repo.aggregate(:count)

    if owner_count <= 1 do
      {:error, :last_owner}
    else
      Repo.delete(membership)
    end
  end

  def remove_member(%Organization{}, %Membership{} = membership) do
    Repo.delete(membership)
  end

  @spec update_member_role(Membership.t(), atom()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def update_member_role(%Membership{} = membership, role) do
    membership
    |> Membership.changeset(%{role: role})
    |> Repo.update()
  end

  @spec get_user_membership(Organization.t(), User.t()) :: Membership.t() | nil
  def get_user_membership(%Organization{} = org, %User{} = user) do
    Repo.get_by(Membership, user_id: user.id, organization_id: org.id)
  end

  @spec list_memberships(Organization.t()) :: [Membership.t()]
  def list_memberships(%Organization{} = org) do
    import Ecto.Query, warn: false

    Membership
    |> where([m], m.organization_id == ^org.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Returns the plan of the user's first organization.
  Used by FunWithFlags.Group protocol for plan-based feature gating.
  """
  @spec get_user_primary_plan(User.t()) :: atom()
  def get_user_primary_plan(%User{} = user) do
    user.id
    |> OrganizationQueries.user_primary_plan()
    |> Repo.one()
    |> case do
      nil -> :free
      plan -> plan
    end
  end
end
