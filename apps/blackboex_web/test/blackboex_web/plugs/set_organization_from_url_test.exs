defmodule BlackboexWeb.Plugs.SetOrganizationFromUrlTest do
  use BlackboexWeb.ConnCase, async: true

  alias BlackboexWeb.Plugs.SetOrganizationFromUrl
  alias BlackboexWeb.UserAuth

  @moduletag :unit

  setup :register_and_log_in_user

  describe "call/2 — SetOrganizationFromUrl" do
    test "sets scope from org_slug in URL", %{conn: conn, user: user} do
      [org] = Blackboex.Organizations.list_user_organizations(user)

      conn =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> Map.put(:params, %{"org_slug" => org.slug})
        |> SetOrganizationFromUrl.call([])

      assert conn.assigns.current_scope.organization.id == org.id
      assert conn.assigns.current_scope.membership.role == :owner
    end

    test "returns 404 for invalid org_slug", %{conn: conn} do
      conn =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> Plug.Conn.put_private(:phoenix_format, "json")
        |> Map.put(:params, %{"org_slug" => "nonexistent-org"})
        |> SetOrganizationFromUrl.call([])

      assert conn.status == 404
      assert conn.halted
    end

    test "passes through when no user in scope" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.assign(:current_scope, nil)
        |> Map.put(:params, %{"org_slug" => "any-org"})
        |> SetOrganizationFromUrl.call([])

      refute conn.halted
    end
  end
end
