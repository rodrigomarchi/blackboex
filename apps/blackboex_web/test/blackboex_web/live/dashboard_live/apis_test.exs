defmodule BlackboexWeb.DashboardLive.ApisTest do
  @moduledoc """
  Tests for the dashboard APIs content in both org and project scopes.
  """
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Organizations
  alias Blackboex.Projects

  @moduletag :liveview

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Organizations.create_organization(user, %{name: "APIs Dashboard Org"})

    project = Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "org scope at /orgs/:slug/settings/apis" do
    test "renders header, nav and stat cards", %{conn: conn, user: user, org: org} do
      api = api_fixture(%{user: user, org: org, name: "Org Scoped API"})
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})
      invocation_log_fixture(%{api_id: api.id, status_code: 500, duration_ms: 100})

      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/settings/apis")

      assert html =~ "Dashboard"
      assert html =~ "APIs"
      assert html =~ "Invocations"
      assert html =~ "Success Rate"
      assert html =~ "Avg Latency"
      assert html =~ "P95 Latency"
      assert html =~ "Org Scoped API"
      # Nav links resolve relative to org base_path
      assert html =~ "/orgs/#{org.slug}/settings"
      assert html =~ "/orgs/#{org.slug}/settings/flows"
    end

    test "renders stat cards with zero values when no invocations", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/settings/apis")

      assert html =~ "Invocations"
      assert html =~ "Success Rate"
      assert html =~ "Avg Latency"
      assert html =~ "P95 Latency"
    end

    test "period selector patches the URL and updates assigns", %{
      conn: conn,
      user: user,
      org: org
    } do
      api = api_fixture(%{user: user, org: org, name: "Period API"})
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 25})

      {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.slug}/settings/apis")

      html = render_patch(lv, ~p"/orgs/#{org.slug}/settings/apis?period=7d")
      assert html =~ "Period API"
      # The 7d pill should now have the active shadow class
      assert html =~ ~s(period=7d)
    end
  end

  describe "project scope at /orgs/:slug/projects/:slug/settings/apis" do
    test "renders project-scoped stats and nav", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      api = api_fixture(%{user: user, org: org, project: project, name: "Project Scope API"})
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 42})

      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/apis")

      assert html =~ "Dashboard"
      assert html =~ "Project Scope API"
      assert html =~ "/orgs/#{org.slug}/projects/#{project.slug}/settings/flows"
    end

    test "excludes invocations from other projects in the same org", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      other_project = project_fixture(%{user: user, org: org, name: "Other Project"})

      other_api =
        api_fixture(%{user: user, org: org, project: other_project, name: "Other Proj API"})

      invocation_log_fixture(%{api_id: other_api.id, status_code: 500, duration_ms: 10})

      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/apis")

      refute html =~ "Other Proj API"
      assert html =~ "Invocations"
    end
  end
end
