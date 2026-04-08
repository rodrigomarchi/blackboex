defmodule Blackboex.FlowsFixtures do
  @moduledoc """
  Test helpers for creating Flow entities.
  """

  alias Blackboex.Flows

  @doc """
  Creates a flow for the given user and organization.

  ## Options

    * `:user` - the owner user (required, or auto-created with org)
    * `:org` - the organization (required, or auto-created with user)
    * `:name` - flow name (default: auto-generated)
    * Any additional attrs are passed through to `Flows.create_flow/1`

  Returns the Flow struct.
  """
  @spec flow_fixture(map()) :: Blackboex.Flows.Flow.t()
  def flow_fixture(attrs \\ %{}) do
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

    known_keys = [:user, :org, :name]
    extra = Map.drop(attrs, known_keys)

    {:ok, flow} =
      Flows.create_flow(
        Map.merge(
          %{
            name: attrs[:name] || "Test Flow #{System.unique_integer([:positive])}",
            organization_id: org.id,
            user_id: user.id
          },
          extra
        )
      )

    flow
  end

  @doc """
  Named setup: creates a flow for existing user + org in context.

  Requires `:user` and `:org` in context.

  Usage: `setup [:register_and_log_in_user, :create_org, :create_flow]`
  """
  @spec create_flow(map()) :: map()
  def create_flow(%{user: user, org: org}) do
    flow = flow_fixture(%{user: user, org: org})
    %{flow: flow}
  end

  @doc """
  Named setup: creates org + flow for existing user in context.

  Requires `:user` in context (e.g. from `register_and_log_in_user`).

  Usage: `setup [:register_and_log_in_user, :create_org_and_flow]`
  """
  @spec create_org_and_flow(map()) :: map()
  def create_org_and_flow(%{user: user}) do
    org = Blackboex.OrganizationsFixtures.org_fixture(%{user: user})
    flow = flow_fixture(%{user: user, org: org})
    %{org: org, flow: flow}
  end
end
