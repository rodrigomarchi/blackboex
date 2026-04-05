defmodule BlackboexWeb.DashboardLiveTest do
  use BlackboexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias Blackboex.Organizations

  @moduletag :liveview

  describe "unauthenticated user" do
    test "redirects to login", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/dashboard")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end

  describe "authenticated user with no APIs" do
    setup :register_and_log_in_user

    test "renders dashboard page title", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Dashboard"
    end

    test "shows welcome empty state when no APIs exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Welcome to BlackBoex"
    end

    test "shows create first API button in empty state", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Create your first API"
    end

    test "shows period selector buttons", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Today"
      assert html =~ "7 days"
      assert html =~ "30 days"
    end
  end

  describe "authenticated user with APIs" do
    setup :register_and_log_in_user

    setup %{user: user} do
      [org] = Organizations.list_user_organizations(user)

      {:ok, api} =
        Apis.create_api(%{
          name: "My Test API",
          description: "A test API",
          status: "published",
          visibility: "public",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, org: org, api: api}
    end

    test "shows stat cards instead of empty state", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Total APIs"
    end

    test "shows API count in stat card", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      # The stat cards section is rendered, meaning total_apis > 0
      assert html =~ "Total APIs"
      assert html =~ "LLM Gens"
    end

    test "does not show empty state when APIs exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      refute html =~ "Welcome to BlackBoex"
    end

    test "shows LLM usage section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "LLM Usage"
    end

    test "shows recent activity section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Recent Activity"
    end

    test "shows top APIs by calls section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Top APIs by Calls"
    end

    test "switching period to 7d updates display", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      html =
        lv
        |> element("button", "7 days")
        |> render_click()

      assert html =~ "7d"
    end

    test "switching period to 30d updates display", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      html =
        lv
        |> element("button", "30 days")
        |> render_click()

      assert html =~ "30d"
    end

    test "invalid period event is ignored and page remains stable", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      # send a bad period — socket should not crash
      lv |> render_hook("set_period", %{"period" => "invalid"})
      assert render(lv) =~ "Dashboard"
    end
  end
end
