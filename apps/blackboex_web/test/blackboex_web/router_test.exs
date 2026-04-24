defmodule BlackboexWeb.RouterTest do
  @moduledoc """
  Tests that exercise untested router routes to improve Router coverage.
  Each test hits a route that hasn't been exercised by other test files.
  """

  use BlackboexWeb.ConnCase, async: true

  @moduletag :unit

  setup :register_and_log_in_user

  describe "authenticated live routes" do
    test "GET /billing renders billing plans page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/billing")
      assert html =~ "Billing" or html =~ "Plan" or html =~ "dashboard"
    end

    test "GET /billing/manage renders billing manage page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/billing/manage")
      assert html =~ "Billing" or html =~ "Manage" or html =~ "dashboard"
    end

    test "GET /api-keys returns 404 (route removed)", %{conn: conn} do
      conn = get(conn, "/api-keys")
      assert conn.status == 404
    end

    test "GET /users/settings renders user settings", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "Settings" or html =~ "Account" or html =~ "Password"
    end
  end

  describe "unauthenticated live routes" do
    test "GET /users/register renders registration page", %{conn: _conn} do
      conn = build_conn()
      {:ok, _lv, html} = live(conn, ~p"/users/register")
      assert html =~ "Register" or html =~ "Sign up" or html =~ "Create"
    end

    test "GET /users/log-in renders login page", %{conn: _conn} do
      conn = build_conn()
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")
      assert html =~ "Log in" or html =~ "Sign in" or html =~ "Email"
    end
  end

  describe "authenticated billing route" do
    test "GET /billing renders plans page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/billing")
      assert html =~ "Plan" or html =~ "plan" or html =~ "Free"
    end
  end

  describe "project-scoped tabs" do
    setup :create_org

    test "GET /orgs/:slug/projects/:slug/api-keys renders ApiKeys LiveView", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/api-keys")
      assert html =~ "API Keys"
    end

    test "GET /orgs/:slug/projects/:slug/env-vars renders EnvVars LiveView", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/env-vars")
      assert html =~ "Env Vars"
    end

    test "GET /orgs/:slug/projects/:slug/integrations renders LlmIntegrations LiveView", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      assert html =~ "LLM Integrations"
    end

    test "GET /orgs/:slug/projects/:slug/integrations unauthenticated redirects to login",
         %{
           org: org,
           project: project
         } do
      anon_conn = build_conn()
      conn = get(anon_conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")
      assert redirected_to(conn) == "/users/log-in"
    end

    test "GET /orgs/:slug/projects/:slug/integrations as non-member returns 403/404",
         %{
           org: org,
           project: project
         } do
      other_user = user_fixture()
      other_conn = build_conn() |> log_in_user(other_user)

      conn = get(other_conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")
      assert conn.status in [403, 404]
    end
  end
end
