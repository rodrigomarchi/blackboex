defmodule Blackboex.Policy.FlowAgentUseTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  alias Blackboex.Policy

  @moduletag :unit

  defp scope_with_role(role) do
    owner = user_fixture()

    {:ok, %{organization: org, membership: membership}} =
      Organizations.create_organization(owner, %{
        name: "flow agent org #{abs(System.unique_integer())}"
      })

    user =
      if role == :owner do
        owner
      else
        member = user_fixture()
        {:ok, _} = Organizations.add_member(org, member, role)
        member
      end

    membership =
      if role == :owner do
        membership
      else
        Organizations.get_user_membership(org, user)
      end

    scope =
      user
      |> Scope.for_user()
      |> Scope.with_organization(org, membership)

    {scope, org}
  end

  describe "authorize/3 :flow_agent_use" do
    test "owner is allowed" do
      {scope, org} = scope_with_role(:owner)
      assert :ok = Policy.authorize(:flow_agent_use, scope, org)
    end

    test "admin is allowed" do
      {scope, org} = scope_with_role(:admin)
      assert :ok = Policy.authorize(:flow_agent_use, scope, org)
    end

    test "member is allowed" do
      {scope, org} = scope_with_role(:member)
      assert :ok = Policy.authorize(:flow_agent_use, scope, org)
    end
  end
end
