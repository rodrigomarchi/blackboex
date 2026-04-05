defmodule Blackboex.PolicyTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  alias Blackboex.Policy

  import Blackboex.AccountsFixtures

  @moduletag :unit

  defp scope_with_role(role) do
    owner = user_fixture()

    {:ok, %{organization: org, membership: membership}} =
      Organizations.create_organization(owner, %{name: "test org #{abs(System.unique_integer())}"})

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

  describe "owner permissions" do
    test "owner can manage any resource in their org" do
      {scope, org} = scope_with_role(:owner)

      assert Policy.authorize?(:organization_create, scope, org)
      assert Policy.authorize?(:organization_read, scope, org)
      assert Policy.authorize?(:organization_update, scope, org)
      assert Policy.authorize?(:organization_delete, scope, org)
      assert Policy.authorize?(:membership_create, scope, org)
      assert Policy.authorize?(:membership_read, scope, org)
      assert Policy.authorize?(:membership_update, scope, org)
      assert Policy.authorize?(:membership_delete, scope, org)
    end
  end

  describe "admin permissions" do
    test "admin can CRUD on organization and membership" do
      {scope, org} = scope_with_role(:admin)

      assert Policy.authorize?(:organization_read, scope, org)
      assert Policy.authorize?(:organization_create, scope, org)
      assert Policy.authorize?(:organization_update, scope, org)
      assert Policy.authorize?(:organization_delete, scope, org)
      assert Policy.authorize?(:membership_create, scope, org)
      assert Policy.authorize?(:membership_read, scope, org)
      assert Policy.authorize?(:membership_update, scope, org)
      assert Policy.authorize?(:membership_delete, scope, org)
    end
  end

  describe "member permissions" do
    test "member can read organization" do
      {scope, org} = scope_with_role(:member)

      assert Policy.authorize?(:organization_read, scope, org)
    end

    test "member can read membership" do
      {scope, org} = scope_with_role(:member)

      assert Policy.authorize?(:membership_read, scope, org)
    end

    test "member cannot create, update, or delete organization" do
      {scope, org} = scope_with_role(:member)

      refute Policy.authorize?(:organization_create, scope, org)
      refute Policy.authorize?(:organization_update, scope, org)
      refute Policy.authorize?(:organization_delete, scope, org)
    end

    test "member cannot create, update, or delete membership" do
      {scope, org} = scope_with_role(:member)

      refute Policy.authorize?(:membership_create, scope, org)
      refute Policy.authorize?(:membership_update, scope, org)
      refute Policy.authorize?(:membership_delete, scope, org)
    end
  end

  describe "api_key permissions" do
    test "owner can create, revoke, and rotate api keys" do
      {scope, org} = scope_with_role(:owner)

      assert Policy.authorize?(:api_key_create, scope, org)
      assert Policy.authorize?(:api_key_revoke, scope, org)
      assert Policy.authorize?(:api_key_rotate, scope, org)
    end

    test "admin can create, revoke, and rotate api keys" do
      {scope, org} = scope_with_role(:admin)

      assert Policy.authorize?(:api_key_create, scope, org)
      assert Policy.authorize?(:api_key_revoke, scope, org)
      assert Policy.authorize?(:api_key_rotate, scope, org)
    end

    test "member cannot create, revoke, or rotate api keys" do
      {scope, org} = scope_with_role(:member)

      refute Policy.authorize?(:api_key_create, scope, org)
      refute Policy.authorize?(:api_key_revoke, scope, org)
      refute Policy.authorize?(:api_key_rotate, scope, org)
    end
  end

  describe "cross-org access" do
    test "user cannot access resources from another org" do
      {scope, _org} = scope_with_role(:owner)
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Organizations.create_organization(other_user, %{name: "Other Org"})

      refute Policy.authorize?(:organization_read, scope, other_org)
      refute Policy.authorize?(:organization_update, scope, other_org)
    end
  end
end
