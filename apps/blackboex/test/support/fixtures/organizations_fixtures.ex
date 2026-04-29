defmodule Blackboex.OrganizationsFixtures do
  @moduledoc """
  Test helpers for creating organization entities.
  """

  alias Blackboex.Organizations

  @doc """
  Creates an organization for the given user.

  If no user is provided, creates one via `AccountsFixtures.user_fixture/0`.

  ## Options

    * `:user` - the user who owns the org (default: new user via user_fixture)
    * `:name` - org name (default: auto-generated unique name)
    * `:slug` - org slug (default: auto-generated unique slug)

  Returns the organization struct.
  """
  @spec org_fixture(map()) :: Blackboex.Organizations.Organization.t()
  def org_fixture(attrs \\ %{}) do
    user = attrs[:user] || Blackboex.AccountsFixtures.user_fixture()
    uid = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    {:ok, %{organization: org}} =
      Organizations.create_organization(user, %{
        name: attrs[:name] || "Test Org #{uid}",
        slug: attrs[:slug] || "testorg#{uid}"
      })

    org
  end

  @doc """
  Creates a user and organization together.

  Returns `{user, org}` tuple.
  """
  @spec user_and_org_fixture(map()) ::
          {Blackboex.Accounts.User.t(), Blackboex.Organizations.Organization.t()}
  def user_and_org_fixture(attrs \\ %{}) do
    user = attrs[:user] || Blackboex.AccountsFixtures.user_fixture()
    org = org_fixture(Map.put(attrs, :user, user))
    {user, org}
  end

  @doc """
  Named setup: creates a user and org, merges into test context.

  Usage: `setup :create_user_and_org`
  """
  @spec create_user_and_org(map()) :: map()
  def create_user_and_org(_context \\ %{}) do
    {user, org} = user_and_org_fixture()
    project = Blackboex.Projects.get_default_project(org.id)
    %{user: user, org: org, project: project}
  end

  @doc """
  Named setup: creates an org for an existing user in context.

  Requires `:user` in context (e.g. from `register_and_log_in_user`).

  Usage: `setup [:register_and_log_in_user, :create_org]`
  """
  @spec create_org(map()) :: map()
  def create_org(%{user: user}) do
    org = org_fixture(%{user: user})
    project = Blackboex.Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  @doc """
  Creates an organization membership for an existing org and user.

  ## Options

    * `:org` - the organization (default: new org via org_fixture)
    * `:user` - the user to add (default: new user via user_fixture)
    * `:role` - membership role (default: :member)

  Returns the membership struct with user preloaded.
  """
  @spec org_member_fixture(map()) :: Blackboex.Organizations.Membership.t()
  def org_member_fixture(attrs \\ %{}) do
    org = attrs[:org] || org_fixture()
    user = attrs[:user] || Blackboex.AccountsFixtures.user_fixture()
    role = attrs[:role] || :member

    {:ok, membership} = Organizations.add_member(org, user, role)
    membership
  end
end
