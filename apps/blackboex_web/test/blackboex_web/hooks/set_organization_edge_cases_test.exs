defmodule BlackboexWeb.Hooks.SetOrganizationEdgeCasesTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  alias BlackboexWeb.Hooks.SetOrganization

  @moduletag :unit

  defp build_socket(assigns) do
    %Phoenix.LiveView.Socket{assigns: Map.put(assigns, :__changed__, %{})}
  end

  describe "edge cases" do
    test "org_id in session points to deleted org — falls back" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)
      scope = Scope.for_user(user)
      socket = build_socket(%{current_scope: scope})

      {:cont, socket} =
        SetOrganization.on_mount(
          :default,
          %{},
          %{"organization_id" => Ecto.UUID.generate()},
          socket
        )

      assert socket.assigns.current_scope.organization.id == org.id
    end

    test "org_id in session where user lost membership — falls back" do
      user = user_fixture()
      [personal_org] = Organizations.list_user_organizations(user)
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Organizations.create_organization(other_user, %{name: "Other Org"})

      scope = Scope.for_user(user)
      socket = build_socket(%{current_scope: scope})

      {:cont, socket} =
        SetOrganization.on_mount(:default, %{}, %{"organization_id" => other_org.id}, socket)

      assert socket.assigns.current_scope.organization.id == personal_org.id
    end
  end
end
