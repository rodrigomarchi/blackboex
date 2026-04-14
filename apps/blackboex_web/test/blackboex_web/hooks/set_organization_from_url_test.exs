defmodule BlackboexWeb.Hooks.SetOrganizationFromUrlTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  alias BlackboexWeb.Hooks.SetOrganizationFromUrl

  @moduletag :unit

  defp build_socket(assigns) do
    %Phoenix.LiveView.Socket{assigns: Map.put(assigns, :__changed__, %{})}
  end

  describe "on_mount :default" do
    test "sets current_scope with org from URL slug" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)
      scope = Scope.for_user(user)
      socket = build_socket(%{current_scope: scope})

      {:cont, socket} =
        SetOrganizationFromUrl.on_mount(:default, %{"org_slug" => org.slug}, %{}, socket)

      assert socket.assigns.current_scope.organization.id == org.id
      assert socket.assigns.current_scope.membership.role == :owner
    end

    test "redirects when org_slug is invalid" do
      user = user_fixture()
      scope = Scope.for_user(user)
      socket = build_socket(%{current_scope: scope})

      {:halt, socket} =
        SetOrganizationFromUrl.on_mount(
          :default,
          %{"org_slug" => "nonexistent-org"},
          %{},
          socket
        )

      assert socket.redirected != nil
    end

    test "continues when no user scope" do
      socket = build_socket(%{current_scope: nil})

      {:cont, ^socket} =
        SetOrganizationFromUrl.on_mount(:default, %{"org_slug" => "any"}, %{}, socket)
    end
  end
end
