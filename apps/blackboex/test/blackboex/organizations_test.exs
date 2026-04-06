defmodule Blackboex.OrganizationsTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Organizations
  alias Blackboex.Organizations.{Membership, Organization}

  @moduletag :unit

  describe "create_organization/2" do
    test "creates org and owner membership atomically" do
      user = user_fixture()

      assert {:ok, %{organization: %Organization{} = org, membership: %Membership{} = mem}} =
               Organizations.create_organization(user, %{name: "Test Org"})

      assert org.name == "Test Org"
      assert org.slug == "test-org"
      assert org.plan == :free
      assert mem.user_id == user.id
      assert mem.organization_id == org.id
      assert mem.role == :owner
    end

    test "fails with invalid attrs" do
      user = user_fixture()
      assert {:error, :organization, _changeset, _} = Organizations.create_organization(user, %{})
    end
  end

  describe "list_user_organizations/1" do
    test "returns orgs the user belongs to" do
      user = user_fixture()
      # user_fixture already creates a personal org, so we expect 1 + 1
      {:ok, %{organization: org}} = Organizations.create_organization(user, %{name: "Org A"})

      orgs = Organizations.list_user_organizations(user)
      assert length(orgs) == 2
      assert Enum.any?(orgs, &(&1.id == org.id))
    end

    test "does not return orgs the user does not belong to" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, _} = Organizations.create_organization(user1, %{name: "Org A"})
      {:ok, _} = Organizations.create_organization(user2, %{name: "Org B"})

      orgs = Organizations.list_user_organizations(user1)
      # personal org + Org A
      assert length(orgs) == 2
      refute Enum.any?(orgs, &(&1.name == "Org B"))
    end
  end

  describe "get_organization!/1" do
    test "returns org by id" do
      user = user_fixture()
      {:ok, %{organization: org}} = Organizations.create_organization(user, %{name: "My Org"})

      found = Organizations.get_organization!(org.id)
      assert found.id == org.id
      assert found.name == "My Org"
    end
  end

  describe "add_member/3" do
    test "adds member with role" do
      owner = user_fixture()
      member = user_fixture()
      {:ok, %{organization: org}} = Organizations.create_organization(owner, %{name: "Team"})

      assert {:ok, %Membership{} = mem} = Organizations.add_member(org, member, :member)
      assert mem.user_id == member.id
      assert mem.organization_id == org.id
      assert mem.role == :member
    end

    test "fails if already a member" do
      owner = user_fixture()
      {:ok, %{organization: org}} = Organizations.create_organization(owner, %{name: "Team"})

      assert {:error, _changeset} = Organizations.add_member(org, owner, :admin)
    end
  end
end
