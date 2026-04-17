defmodule BlackboexWeb.Hooks.SetPreferredProject do
  @moduledoc """
  LiveView on_mount hook used on org-scoped routes (e.g. the org dashboard).

  When the scope carries an organization but no project, populates the scope
  with the user's last-visited project for that org (or falls back to the
  Default/first accessible project) so the sidebar can continue to reflect
  the current project context even on org-level pages.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Blackboex.Accounts.Scope
  alias Blackboex.Projects
  alias BlackboexWeb.LastVisited

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    scope = socket.assigns[:current_scope]

    case scope do
      %Scope{user: user, organization: org, project: nil}
      when not is_nil(user) and not is_nil(org) ->
        case LastVisited.resolve_project_for_org(user, org) do
          {:ok, project} ->
            pm = Projects.get_project_membership(project, user)
            {:cont, assign(socket, :current_scope, Scope.with_project(scope, project, pm))}

          :none ->
            {:cont, socket}
        end

      _ ->
        {:cont, socket}
    end
  end
end
