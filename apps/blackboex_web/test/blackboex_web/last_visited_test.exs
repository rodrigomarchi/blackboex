defmodule BlackboexWeb.LastVisitedTest do
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Accounts
  alias Blackboex.Organizations
  alias Blackboex.Projects
  alias BlackboexWeb.LastVisited

  describe "resolve/1" do
    setup do
      # user_fixture registers the user, which seeds a personal org + Default project.
      user = user_fixture()
      [personal_org | _] = Organizations.list_user_organizations(user)
      personal_default = Projects.get_default_project(personal_org.id)
      %{user: user, personal_org: personal_org, personal_default: personal_default}
    end

    test "returns the user's personal org + its Default project with no last-visited", %{
      user: user,
      personal_org: org,
      personal_default: default
    } do
      assert {:ok, resolved_org, resolved_project} = LastVisited.resolve(user)
      assert resolved_org.id == org.id
      assert resolved_project.id == default.id
    end

    test "prefers persisted last_organization + last_project across multiple orgs", %{
      user: user
    } do
      second_org = org_fixture(%{user: user})
      second_project = project_fixture(%{user: user, org: second_org})

      {:ok, user} = Accounts.touch_last_visited(user, second_org.id, second_project.id)

      assert {:ok, resolved_org, resolved_project} = LastVisited.resolve(user)
      assert resolved_org.id == second_org.id
      assert resolved_project.id == second_project.id
    end

    test "falls back to the stored org's Default project when last_project is stale", %{
      user: user,
      personal_org: org,
      personal_default: default
    } do
      # FK would nilify a dangling id in practice; here we fake it in-memory to
      # exercise the resolver's fallback branch.
      stale = %{user | last_organization_id: org.id, last_project_id: Ecto.UUID.generate()}

      assert {:ok, resolved_org, resolved_project} = LastVisited.resolve(stale)
      assert resolved_org.id == org.id
      assert resolved_project.id == default.id
    end

    test "falls back to first org when the stored org is unreachable", %{
      user: user,
      personal_org: personal_org
    } do
      stale = %{user | last_organization_id: Ecto.UUID.generate(), last_project_id: nil}

      assert {:ok, resolved_org, _} = LastVisited.resolve(stale)
      assert resolved_org.id == personal_org.id
    end
  end

  describe "Accounts.touch_last_visited/3" do
    setup do
      user = user_fixture()
      [org | _] = Organizations.list_user_organizations(user)
      project = Projects.get_default_project(org.id)
      %{user: user, org: org, project: project}
    end

    test "writes when values change", %{user: user, org: org, project: project} do
      {:ok, updated} = Accounts.touch_last_visited(user, org.id, project.id)

      assert updated.last_organization_id == org.id
      assert updated.last_project_id == project.id
    end

    test "is a noop when values already match", %{user: user, org: org} do
      {:ok, user} = Accounts.touch_last_visited(user, org.id, nil)
      updated_at = user.updated_at

      {:ok, user2} = Accounts.touch_last_visited(user, org.id, nil)

      assert user2.updated_at == updated_at
    end
  end
end
