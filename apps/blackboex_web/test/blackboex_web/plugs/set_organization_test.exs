defmodule BlackboexWeb.Plugs.SetOrganizationTest do
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Organizations
  alias BlackboexWeb.Plugs.SetOrganization
  alias BlackboexWeb.UserAuth

  @moduletag :unit

  setup :register_and_log_in_user

  describe "call/2" do
    test "loads org from session org_id", %{conn: conn, user: user} do
      [org] = Organizations.list_user_organizations(user)

      conn =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> Plug.Conn.put_session(:organization_id, org.id)
        |> SetOrganization.call([])

      assert conn.assigns.current_scope.organization.id == org.id
      assert conn.assigns.current_scope.membership.role == :owner
    end

    test "falls back to first org when no org_id in session", %{conn: conn, user: user} do
      [org] = Organizations.list_user_organizations(user)

      conn =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> SetOrganization.call([])

      assert conn.assigns.current_scope.organization.id == org.id
    end

    test "passes through when no user" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.assign(:current_scope, nil)
        |> SetOrganization.call([])

      assert conn.assigns.current_scope == nil
    end
  end
end
