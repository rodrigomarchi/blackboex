defmodule BlackboexWeb.Hooks.SetOrganizationFromUrl do
  @moduledoc """
  LiveView on_mount hook that sets the current organization from the
  `:org_slug` URL param.

  Used in new `/orgs/:org_slug/*` live routes. Redirects to the user's
  first organization if the slug is invalid or the user has no membership.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, %{"org_slug" => org_slug}, _session, socket) do
    scope = socket.assigns.current_scope

    case scope do
      %Scope{user: user} when not is_nil(user) ->
        set_organization(socket, scope, user, org_slug)

      _ ->
        {:cont, socket}
    end
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}

  defp set_organization(socket, scope, user, org_slug) do
    with %{} = org <- Organizations.get_organization_by_slug(org_slug),
         %{} = membership <- Organizations.get_user_membership(org, user) do
      {:cont, assign(socket, :current_scope, Scope.with_organization(scope, org, membership))}
    else
      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/users/log-in")}
    end
  end
end
