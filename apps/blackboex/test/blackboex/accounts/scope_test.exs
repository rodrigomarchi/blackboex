defmodule Blackboex.Accounts.ScopeTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations

  @moduletag :unit

  describe "for_user/1" do
    test "creates scope with user" do
      user = user_fixture()
      scope = Scope.for_user(user)
      assert scope.user.id == user.id
      assert scope.organization == nil
      assert scope.membership == nil
    end

    test "returns nil for nil user" do
      assert Scope.for_user(nil) == nil
    end
  end

  describe "with_organization/3" do
    test "sets organization and membership on scope" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)
      membership = Organizations.get_user_membership(org, user)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

      assert scope.user.id == user.id
      assert scope.organization.id == org.id
      assert scope.membership.id == membership.id
    end
  end
end
