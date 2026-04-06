defmodule Blackboex.PolicyEdgeCasesTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  alias Blackboex.Policy

  @moduletag :unit

  describe "nil scope" do
    test "nil scope is not authorized" do
      {_user, org} = user_and_org_fixture()

      refute Policy.authorize?(:organization_read, nil, org)
    end
  end

  describe "scope without organization" do
    test "scope with user only but no org is not authorized" do
      {user, org} = user_and_org_fixture()
      scope = Scope.for_user(user)

      refute Policy.authorize?(:organization_read, scope, org)
    end
  end

  describe "member boundary enforcement" do
    test "member cannot create membership" do
      owner = user_fixture()
      member_user = user_fixture()

      {:ok, %{organization: org}} =
        Organizations.create_organization(owner, %{name: "Test Org"})

      {:ok, _} = Organizations.add_member(org, member_user, :member)
      membership = Organizations.get_user_membership(org, member_user)

      scope =
        member_user
        |> Scope.for_user()
        |> Scope.with_organization(org, membership)

      refute Policy.authorize?(:membership_create, scope, org)
      refute Policy.authorize?(:membership_update, scope, org)
      refute Policy.authorize?(:membership_delete, scope, org)
    end
  end

  describe "non-existent action" do
    @tag :capture_log
    test "undefined action returns false" do
      {user, org} = user_and_org_fixture()
      membership = Organizations.get_user_membership(org, user)

      scope =
        user
        |> Scope.for_user()
        |> Scope.with_organization(org, membership)

      refute Policy.authorize?(:nonexistent_action, scope, org)
    end
  end
end
