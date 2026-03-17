defmodule BlackboexWeb.Hooks.SetOrganization do
  @moduledoc """
  LiveView on_mount hook that sets the current organization on the scope.

  Loads from session `organization_id`. Falls back to user's first org
  if the org doesn't exist, user lost membership, or no org_id is set.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    scope = socket.assigns.current_scope

    case scope do
      %Scope{user: user} when not is_nil(user) ->
        org_id = session["organization_id"]
        socket = set_organization(socket, scope, user, org_id)
        {:cont, socket}

      _ ->
        {:cont, socket}
    end
  end

  defp set_organization(socket, scope, user, org_id) when is_binary(org_id) do
    with %{} = org <- Organizations.get_organization(org_id),
         %{} = membership <- Organizations.get_user_membership(org, user) do
      assign(socket, :current_scope, Scope.with_organization(scope, org, membership))
    else
      _ -> fallback_to_first_org(socket, scope, user)
    end
  end

  defp set_organization(socket, scope, user, _nil) do
    fallback_to_first_org(socket, scope, user)
  end

  defp fallback_to_first_org(socket, scope, user) do
    case Organizations.list_user_organizations(user) do
      [org | _] ->
        membership = Organizations.get_user_membership(org, user)

        if membership do
          assign(socket, :current_scope, Scope.with_organization(scope, org, membership))
        else
          socket
        end

      [] ->
        socket
    end
  end
end
