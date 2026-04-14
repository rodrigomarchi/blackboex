defmodule BlackboexWeb.Hooks.SetDefaultProject do
  @moduledoc """
  LiveView on_mount hook that loads the default project into scope.

  Only sets the project if the scope already has an organization but no project.
  Used so navigation and LiveViews can build project-scoped URLs.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Blackboex.Accounts.Scope
  alias Blackboex.Projects

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    scope = socket.assigns.current_scope

    case scope do
      %Scope{organization: org, project: nil} when not is_nil(org) ->
        case Projects.get_default_project(org.id) do
          nil ->
            {:cont, socket}

          project ->
            pm = Projects.get_project_membership(project, scope.user)
            {:cont, assign(socket, :current_scope, Scope.with_project(scope, project, pm))}
        end

      _ ->
        {:cont, socket}
    end
  end
end
