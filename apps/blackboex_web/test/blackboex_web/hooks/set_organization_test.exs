defmodule BlackboexWeb.Hooks.SetOrganizationTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  alias BlackboexWeb.Hooks.SetOrganization

  import Blackboex.AccountsFixtures

  @moduletag :unit

  defp build_socket(assigns) do
    %Phoenix.LiveView.Socket{assigns: Map.put(assigns, :__changed__, %{})}
  end

  describe "on_mount :default" do
    test "loads user's first org when none in session" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)
      scope = Scope.for_user(user)
      socket = build_socket(%{current_scope: scope})

      {:cont, socket} = SetOrganization.on_mount(:default, %{}, %{}, socket)

      assert socket.assigns.current_scope.organization.id == org.id
      assert socket.assigns.current_scope.membership.role == :owner
    end

    test "loads org from session org_id" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)
      scope = Scope.for_user(user)
      socket = build_socket(%{current_scope: scope})

      {:cont, socket} =
        SetOrganization.on_mount(:default, %{}, %{"organization_id" => org.id}, socket)

      assert socket.assigns.current_scope.organization.id == org.id
    end

    test "continues when no user scope" do
      socket = build_socket(%{current_scope: nil})

      {:cont, ^socket} = SetOrganization.on_mount(:default, %{}, %{}, socket)
    end
  end
end
