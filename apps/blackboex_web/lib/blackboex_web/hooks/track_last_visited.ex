defmodule BlackboexWeb.Hooks.TrackLastVisited do
  @moduledoc """
  Persists the user's current organization + project as the last-visited
  workspace. Runs after the scope hooks so it sees the resolved IDs.

  Only writes when the value changed to keep login pages and idle navigation
  from causing spurious writes.
  """

  alias Blackboex.Accounts
  alias Blackboex.Accounts.Scope

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_scope] do
      %Scope{user: user, organization: org} = scope when not is_nil(user) and not is_nil(org) ->
        project_id = scope.project && scope.project.id
        _ = Accounts.touch_last_visited(user, org.id, project_id)
        {:cont, socket}

      _ ->
        {:cont, socket}
    end
  end
end
