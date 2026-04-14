defmodule BlackboexWeb.OrgProjectRoutesTest do
  @moduledoc """
  Tests for the new /orgs/:org_slug/... and /orgs/:org_slug/projects/:project_slug/... routes.
  """

  use BlackboexWeb.ConnCase, async: true

  @moduletag :liveview

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org"})

    project = Blackboex.Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "org-level routes" do
    test "GET /orgs/:slug renders org dashboard", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}")
      assert html =~ "Dashboard" or html =~ "Org"
    end

    test "GET /orgs/invalid returns 404", %{conn: conn} do
      conn = get(conn, "/orgs/nonexistent-invalid-org")
      assert conn.status == 404
    end
  end

  describe "project-level routes" do
    test "GET /orgs/:slug/projects/:slug renders project dashboard", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}")
      assert html =~ "Dashboard" or html =~ "Project"
    end

    test "GET /orgs/:slug/projects/:slug/apis renders API list", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/apis")
      assert html =~ "API" or html =~ "api"
    end

    test "GET /orgs/:slug/projects/invalid returns 404", %{conn: conn, org: org} do
      conn = get(conn, "/orgs/#{org.slug}/projects/nonexistent-invalid-project")
      assert conn.status == 404
    end
  end
end
