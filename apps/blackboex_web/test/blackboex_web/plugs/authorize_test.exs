defmodule BlackboexWeb.Plugs.AuthorizeTest do
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  alias BlackboexWeb.Plugs.Authorize
  alias BlackboexWeb.UserAuth

  @moduletag :unit

  setup :register_and_log_in_user

  test "allows authorized action", %{conn: conn, user: user} do
    [org] = Organizations.list_user_organizations(user)
    membership = Organizations.get_user_membership(org, user)

    scope =
      user
      |> Scope.for_user()
      |> Scope.with_organization(org, membership)

    conn =
      conn
      |> Plug.Conn.assign(:current_scope, scope)
      |> Plug.Conn.assign(:authorization_object, org)
      |> Authorize.call(action: :organization_read)

    refute conn.halted
  end

  test "halts unauthorized action", %{conn: conn} do
    member = Blackboex.AccountsFixtures.user_fixture()
    owner = Blackboex.AccountsFixtures.user_fixture()

    {:ok, %{organization: org}} =
      Organizations.create_organization(owner, %{name: "Other Org"})

    {:ok, _} = Organizations.add_member(org, member, :member)
    membership = Organizations.get_user_membership(org, member)

    scope =
      member
      |> Scope.for_user()
      |> Scope.with_organization(org, membership)

    conn =
      conn
      |> UserAuth.fetch_current_scope_for_user([])
      |> Plug.Conn.assign(:current_scope, scope)
      |> Plug.Conn.assign(:authorization_object, org)
      |> Authorize.call(action: :organization_delete)

    assert conn.halted
    assert conn.status == 403
  end
end
