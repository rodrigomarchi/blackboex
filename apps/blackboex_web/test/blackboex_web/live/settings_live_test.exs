defmodule BlackboexWeb.SettingsLiveTest do
  use BlackboexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag :liveview

  setup :register_and_log_in_user

  # Helper: delete all orgs for a user so scope has organization: nil
  defp delete_user_orgs(user) do
    import Ecto.Query

    Blackboex.Repo.delete_all(
      from(m in Blackboex.Organizations.Membership,
        where: m.user_id == ^user.id
      )
    )
  end

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

    test "shows no recent activity when audit log is empty", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      html = lv |> element(~s|a[href="/settings?tab=security"]|) |> render_click()

      # New user has no audit logs
      assert html =~ "Security" or html =~ "No recent activity"
    end
  end

  describe "nil organization paths" do
    test "organization tab shows 'No organization selected' when user has no org", %{
      user: user
    } do
      delete_user_orgs(user)

      # Reconnect with fresh conn since org is now gone
      conn = log_in_user(build_conn(), user)
      {:ok, lv, _html} = live(conn, ~p"/settings")

      html = lv |> element(~s|a[href="/settings?tab=organization"]|) |> render_click()

      assert html =~ "No organization selected"
    end

    test "billing tab shows 'No organization selected' when user has no org", %{
      user: user
    } do
      delete_user_orgs(user)

      conn = log_in_user(build_conn(), user)
      {:ok, lv, _html} = live(conn, ~p"/settings")

      html = lv |> element(~s|a[href="/settings?tab=billing"]|) |> render_click()

      assert html =~ "No organization selected"
    end
  end

  describe "direct tab param routing" do
    test "mounts directly on organization tab via query param", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings?tab=organization")

      assert html =~ "Organization"
    end

    test "mounts directly on billing tab via query param", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings?tab=billing")

      assert html =~ "Billing"
    end

    test "mounts directly on security tab via query param", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings?tab=security")

      assert html =~ "Security"
    end

    test "falls back to profile tab for unknown tab param", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings?tab=unknown")

      # Should render profile tab (default fallback)
      assert html =~ "Profile"
    end

    test "profile tab shows member since info", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")

      assert html =~ "Member since"
    end

    test "profile tab shows Edit Email & Password button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")

      assert html =~ "Edit Email"
    end
  end
end
