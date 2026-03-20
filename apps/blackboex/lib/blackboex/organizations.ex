defmodule Blackboex.Organizations do
  @moduledoc """
  The Organizations context. Manages organizations, memberships, and multi-tenancy.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Accounts.User
  alias Blackboex.Audit
  alias Blackboex.Organizations.{Membership, Organization}
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
    |> Repo.transaction()
  end

  @spec list_user_organizations(User.t()) :: [Organization.t()]
  def list_user_organizations(%User{} = user) do
    Organization
    |> join(:inner, [o], m in Membership, on: m.organization_id == o.id)
    |> where([_o, m], m.user_id == ^user.id)
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
        Task.Supervisor.start_child(Blackboex.LoggingSupervisor, fn ->
          Audit.log("member.added", %{
            resource_type: "membership",
            resource_id: membership.id,
            organization_id: org.id,
            user_id: user.id
          })
        end)

        {:ok, membership}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec get_user_membership(Organization.t(), User.t()) :: Membership.t() | nil
  def get_user_membership(%Organization{} = org, %User{} = user) do
    Repo.get_by(Membership, user_id: user.id, organization_id: org.id)
  end

  @doc """
  Returns the plan of the user's first organization.
  Used by FunWithFlags.Group protocol for plan-based feature gating.
  """
  @spec get_user_primary_plan(User.t()) :: atom()
  def get_user_primary_plan(%User{} = user) do
    Organization
    |> join(:inner, [o], m in Membership, on: m.organization_id == o.id)
    |> where([_o, m], m.user_id == ^user.id)
    |> order_by([_o, m], asc: m.inserted_at)
    |> limit(1)
    |> select([o], o.plan)
    |> Repo.one()
    |> case do
      nil -> :free
      plan -> plan
    end
  end
end
