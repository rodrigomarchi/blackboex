defmodule BlackboexWeb.Plugs.RequirePlatformAdminTest do
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Accounts.Scope
  alias BlackboexWeb.Plugs.RequirePlatformAdmin

  import Blackboex.AccountsFixtures

  @moduletag :unit

  describe "call/2" do
    test "allows platform admin through", %{conn: conn} do
      user = user_fixture(%{is_platform_admin: true})
      scope = Scope.for_user(user)

      conn =
        conn
        |> Plug.Conn.assign(:current_scope, scope)
        |> RequirePlatformAdmin.call([])

      refute conn.halted
    end

    test "redirects non-admin user to dashboard", %{conn: conn} do
      user = user_fixture()
      scope = Scope.for_user(user)

      conn =
        conn
        |> init_test_session(%{})
        |> Plug.Conn.assign(:current_scope, scope)
        |> fetch_flash()
        |> RequirePlatformAdmin.call([])

      assert conn.halted
      assert redirected_to(conn) == "/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not authorized"
    end

    test "redirects when no scope is set", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequirePlatformAdmin.call([])

      assert conn.halted
      assert redirected_to(conn) == "/dashboard"
    end
  end
end
