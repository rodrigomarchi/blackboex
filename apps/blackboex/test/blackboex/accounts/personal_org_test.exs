defmodule Blackboex.Accounts.PersonalOrgTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts
  alias Blackboex.Organizations

  @moduletag :unit

  describe "register_user/1 personal organization" do
    test "creates a personal organization on registration" do
      {:ok, user} =
        Accounts.register_user(%{email: "test-#{System.unique_integer()}@example.com"})

      orgs = Organizations.list_user_organizations(user)
      assert length(orgs) == 1

      org = hd(orgs)
      assert org.plan == :free

      membership = Organizations.get_user_membership(org, user)
      assert membership.role == :owner
    end
  end
end
