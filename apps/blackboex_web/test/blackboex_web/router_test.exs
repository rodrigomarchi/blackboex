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

    test "GET /api-keys renders api keys index", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/api-keys")
      assert html =~ "API Keys" or html =~ "api-keys" or html =~ "Keys"
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
end
