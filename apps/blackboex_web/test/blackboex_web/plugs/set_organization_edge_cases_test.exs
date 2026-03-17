defmodule BlackboexWeb.Plugs.SetOrganizationEdgeCasesTest do
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Organizations
  alias BlackboexWeb.Plugs.SetOrganization
  alias BlackboexWeb.UserAuth

  @moduletag :unit

  setup :register_and_log_in_user

  describe "edge cases" do
    test "org_id in session points to deleted org — falls back", %{conn: conn, user: user} do
      [org] = Organizations.list_user_organizations(user)

      conn =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> Plug.Conn.put_session(:organization_id, Ecto.UUID.generate())
        |> SetOrganization.call([])

      # Should fallback to first org
      assert conn.assigns.current_scope.organization.id == org.id
    end

    test "org_id in session where user lost membership — falls back", %{conn: conn, user: user} do
      other_user = Blackboex.AccountsFixtures.user_fixture()

      {:ok, %{organization: other_org}} =
        Organizations.create_organization(other_user, %{name: "Other Org"})

      conn =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> Plug.Conn.put_session(:organization_id, other_org.id)
        |> SetOrganization.call([])

      # user is not a member of other_org, so falls back to personal org
      [personal_org] = Organizations.list_user_organizations(user)
      assert conn.assigns.current_scope.organization.id == personal_org.id
    end
  end
end
