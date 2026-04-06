defmodule Blackboex.OrganizationsEdgeCasesTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Organizations

  @moduletag :unit

  describe "get_organization/1" do
    test "returns nil for non-existent id" do
      assert Organizations.get_organization(Ecto.UUID.generate()) == nil
    end

    test "returns org for valid id" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)
      assert Organizations.get_organization(org.id) != nil
    end
  end

  describe "get_user_membership/2 edge cases" do
    test "returns nil when user has no membership" do
      user1 = user_fixture()
      user2 = user_fixture()
      [org] = Organizations.list_user_organizations(user1)

      assert Organizations.get_user_membership(org, user2) == nil
    end
  end

  describe "cascade deletion" do
    test "deleting user cascades memberships" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)

      assert Organizations.get_user_membership(org, user) != nil

      Blackboex.Repo.delete!(user)

      assert Organizations.get_user_membership(org, %{user | id: user.id}) == nil
    end
  end

  describe "personal org uniqueness" do
    test "two users with same email prefix get different orgs" do
      {:ok, user1} = Blackboex.Accounts.register_user(%{email: "john@example.com"})
      {:ok, user2} = Blackboex.Accounts.register_user(%{email: "john@other.com"})

      [org1] = Organizations.list_user_organizations(user1)
      [org2] = Organizations.list_user_organizations(user2)

      assert org1.slug != org2.slug
    end
  end
end
