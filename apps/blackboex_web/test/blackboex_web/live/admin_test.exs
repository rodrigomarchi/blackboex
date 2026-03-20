defmodule BlackboexWeb.AdminLiveTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  describe "non-admin user authorization" do
    setup :register_and_log_in_user

    test "non-admin cannot access /admin dashboard", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/admin")
    end

    test "non-admin cannot access /admin/users", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/admin/users")
    end

    test "non-admin cannot access /admin/organizations", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/admin/organizations")
    end

    test "non-admin cannot access /admin/apis", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/admin/apis")
    end

    test "non-admin cannot access /admin/subscriptions", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/admin/subscriptions")
    end

    test "non-admin cannot access /admin/audit-logs", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/admin/audit-logs")
    end
  end

  describe "unauthenticated user authorization" do
    test "unauthenticated user cannot access /admin", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, "/admin")
    end
  end

  describe "admin user access" do
    setup %{conn: conn} do
      user = Blackboex.AccountsFixtures.user_fixture(%{is_platform_admin: true})
      conn = log_in_user(conn, user)

      # Admin needs an organization for the SetOrganization hook
      {:ok, %{organization: org}} =
        Blackboex.Organizations.create_organization(user, %{
          name: "Admin Org",
          slug: "admin-org-#{System.unique_integer([:positive])}"
        })

      %{conn: conn, user: user, org: org}
    end

    test "admin can access /admin dashboard", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/admin")
      assert html =~ "Admin Dashboard"
    end

    test "admin dashboard shows platform statistics", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/admin")
      assert html =~ "Users"
      assert html =~ "Organizations"
      assert html =~ "APIs"
    end

    test "admin can access /admin/users", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/admin/users")
      assert html =~ "Users"
    end

    test "admin can access /admin/organizations", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/admin/organizations")
      assert html =~ "Organizations"
    end
  end
end
