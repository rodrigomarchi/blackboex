defmodule BlackboexWeb.DashboardLive.OverviewTest do
  @moduledoc """
  Tests for the dashboard Overview content in both org and project scopes.
  """
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Organizations
  alias Blackboex.Projects

  @moduletag :liveview

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Organizations.create_organization(user, %{name: "Overview Org"})

    project = Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "org scope at /orgs/:slug/settings" do
    test "renders overview header and nav with org base_path", %{conn: conn, user: user, org: org} do
      api_fixture(%{user: user, org: org, name: "Org Scope API"})

      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/settings")

      assert html =~ "Dashboard"
      assert html =~ "Total APIs"
      assert html =~ "Total Flows"
      assert html =~ "Invocations (24h)"
      assert html =~ "Errors (24h)"
      # Nav links resolve relative to org base_path
      assert html =~ "/orgs/#{org.slug}/settings/apis"
      assert html =~ "/orgs/#{org.slug}/settings/flows"
    end
  end

  describe "project scope at /orgs/:slug/projects/:slug/settings" do
    test "renders project-scoped stats and nav", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      api = api_fixture(%{user: user, org: org, project: project, name: "Project Scope API"})
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 42})

      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings")

      assert html =~ "Dashboard"
      assert html =~ "Total APIs"
      assert html =~ "Project Scope API"
      # Nav uses project base_path
      assert html =~ "/orgs/#{org.slug}/projects/#{project.slug}/settings/apis"
    end

    test "excludes data from other projects in same org", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      other_project = project_fixture(%{user: user, org: org, name: "Other Project"})

      other_api =
        api_fixture(%{user: user, org: org, project: other_project, name: "Other Project API"})

      invocation_log_fixture(%{api_id: other_api.id, status_code: 500, duration_ms: 10})

      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings")

      refute html =~ "Other Project API"
    end
  end

  describe "empty state" do
    test "renders stat cards with zero values when nothing exists", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings")

      assert html =~ "Total APIs"
      assert html =~ "Total Flows"
      assert html =~ "Invocations (24h)"
      assert html =~ "Errors (24h)"
    end
  end
end
