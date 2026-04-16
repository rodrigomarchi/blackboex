defmodule BlackboexWeb.PlaygroundLive.Index do
  @moduledoc """
  Redirects to the playground editor. If no playgrounds exist, creates one first.
  The listing is now handled by the sidebar in the Edit view.
  """
  use BlackboexWeb, :live_view

  alias Blackboex.Playgrounds

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    project = scope.project

    case Playgrounds.list_playgrounds(project.id) do
      [first | _] ->
        {:ok, push_navigate(socket, to: playground_edit_path(scope, first))}

      [] ->
        attrs = %{
          name: "Untitled",
          organization_id: project.organization_id,
          project_id: project.id,
          user_id: scope.user.id
        }

        case Playgrounds.create_playground(attrs) do
          {:ok, pg} ->
            {:ok, push_navigate(socket, to: playground_edit_path(scope, pg))}

          {:error, _changeset} ->
            {:ok,
             socket
             |> put_flash(:error, "Failed to create playground")
             |> push_navigate(to: project_path(scope, "/"))}
        end
    end
  end

  defp playground_edit_path(scope, playground) do
    project_path(scope, "/playgrounds/#{playground.slug}/edit")
  end
end
