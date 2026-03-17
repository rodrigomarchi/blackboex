defmodule BlackboexWeb.Plugs.AuthorizeEdgeCasesTest do
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.AccountsFixtures
  alias Blackboex.Organizations
  alias BlackboexWeb.Plugs.Authorize

  @moduletag :unit

  test "halts with 403 when current_scope is nil", %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.assign(:current_scope, nil)
      |> Plug.Conn.assign(:authorization_object, %{})
      |> Authorize.call(action: :organization_read)

    assert conn.halted
    assert conn.status == 403
  end

  test "halts with 403 when authorization_object is nil", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    [org] = Organizations.list_user_organizations(user)
    membership = Organizations.get_user_membership(org, user)

    scope =
      user
      |> Scope.for_user()
      |> Scope.with_organization(org, membership)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.assign(:current_scope, scope)
      |> Plug.Conn.assign(:authorization_object, nil)
      |> Authorize.call(action: :organization_read)

    assert conn.halted
    assert conn.status == 403
  end
end
