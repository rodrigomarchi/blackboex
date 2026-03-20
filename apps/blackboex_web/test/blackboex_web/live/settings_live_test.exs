defmodule BlackboexWeb.SettingsLiveTest do
  use BlackboexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag :liveview

  setup :register_and_log_in_user

  describe "profile tab" do
    test "renders profile information", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/settings")

      assert html =~ "Settings"
      assert html =~ "Profile"
      assert html =~ user.email
    end
  end

  describe "organization tab" do
    test "renders organization information", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      html = lv |> element(~s|a[href="/settings?tab=organization"]|) |> render_click()

      assert html =~ "Organization"
      assert html =~ "Members"
    end
  end

  describe "billing tab" do
    test "renders billing information", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      html = lv |> element(~s|a[href="/settings?tab=billing"]|) |> render_click()

      assert html =~ "Billing"
      assert html =~ "Current Plan"
      assert html =~ "View Plans"
    end
  end

  describe "security tab" do
    test "renders security information", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      html = lv |> element(~s|a[href="/settings?tab=security"]|) |> render_click()

      assert html =~ "Security"
    end
  end
end
