defmodule BlackboexWeb.DashboardLiveTest do
  use BlackboexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @moduletag :liveview

  describe "authenticated user" do
    setup :register_and_log_in_user

    test "renders dashboard page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Dashboard"
    end

    test "shows welcome message", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Welcome"
    end

    test "shows create API button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Create API"
    end
  end

  describe "unauthenticated user" do
    test "redirects to login", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/dashboard")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end
end
