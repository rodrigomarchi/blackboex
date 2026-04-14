defmodule BlackboexWeb.Hooks.SetProjectFromUrl do
  @moduledoc """
  LiveView on_mount hook that sets the current project from the
  `:project_slug` URL param.

  Requires `SetOrganizationFromUrl` (or equivalent) to have run first so
  that `current_scope` already carries the organization and membership.

  - Redirects to login when the project slug is invalid.
  - Redirects to login when the user has no access to the project.
  - Org owners and admins get implicit access (project_membership = nil).
  """

  import Phoenix.Component, only: [assign: 3]

  alias Blackboex.Accounts.Scope
  alias Blackboex.Projects

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, %{"project_slug" => project_slug}, _session, socket) do
    case socket.assigns.current_scope do
      %Scope{organization: org, membership: membership} = scope
      when not is_nil(org) and not is_nil(membership) ->
        set_project(socket, scope, org, membership, project_slug)

      _ ->
        {:cont, socket}
    end
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}

  defp set_project(socket, scope, org, membership, project_slug) do
    case Projects.get_project_by_slug(org.id, project_slug) do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/users/log-in")}

      project ->
        resolve_access(socket, scope, membership, project)
    end
  end

  defp resolve_access(socket, scope, membership, project) do
    if membership.role in [:owner, :admin] do
      {:cont, assign(socket, :current_scope, Scope.with_project(scope, project, nil))}
    else
      user = scope.user

      case Projects.get_project_membership(project, user) do
        nil ->
          {:halt, Phoenix.LiveView.redirect(socket, to: "/users/log-in")}

        project_membership ->
          {:cont,
           assign(socket, :current_scope, Scope.with_project(scope, project, project_membership))}
      end
    end
  end
end
