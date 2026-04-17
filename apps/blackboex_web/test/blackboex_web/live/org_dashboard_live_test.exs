defmodule BlackboexWeb.OrgDashboardLiveTest do
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Accounts
  alias Blackboex.Organizations
  alias Blackboex.Projects

  @moduletag :liveview

  describe "mount" do
    setup :register_and_log_in_user

    test "redirects to the org's Default project on first visit", %{conn: conn, user: user} do
      [org | _] = Organizations.list_user_organizations(user)
      default = Projects.get_default_project(org.id)

      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/orgs/#{org.slug}")
      assert path == "/orgs/#{org.slug}/projects/#{default.slug}"
    end

    test "redirects to last_project_id when it belongs to the org", %{conn: conn, user: user} do
      [org | _] = Organizations.list_user_organizations(user)
      other_project = project_fixture(%{user: user, org: org, name: "Side"})
      {:ok, _} = Accounts.touch_last_visited(user, org.id, other_project.id)

      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/orgs/#{org.slug}")
      assert path == "/orgs/#{org.slug}/projects/#{other_project.slug}"
    end

    test "/orgs/:slug/dashboard renders the new Overview without redirecting", %{
      conn: conn,
      user: user
    } do
      [org | _] = Organizations.list_user_organizations(user)

      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/dashboard")

      assert html =~ "Dashboard"
      assert html =~ "Total APIs"
    end

    test "ignores last_project_id from a different org", %{conn: conn, user: user} do
      [personal_org | _] = Organizations.list_user_organizations(user)
      second_org = org_fixture(%{user: user})
      project_in_second = project_fixture(%{user: user, org: second_org})
      {:ok, _} = Accounts.touch_last_visited(user, second_org.id, project_in_second.id)

      default = Projects.get_default_project(personal_org.id)

      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/orgs/#{personal_org.slug}")
      assert path == "/orgs/#{personal_org.slug}/projects/#{default.slug}"
    end
  end
end
