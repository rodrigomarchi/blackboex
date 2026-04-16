defmodule BlackboexWeb.PageLive.Index do
  @moduledoc """
  Redirects to the page editor. If the project has pages, navigates to the
  first one. Otherwise creates an "Untitled" page and redirects to it.
  """
  use BlackboexWeb, :live_view

  alias Blackboex.Pages

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.project do
      {:ok, redirect_to_editor(socket, scope)}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div></div>
    """
  end

  defp redirect_to_editor(socket, scope) do
    case Pages.list_pages(scope.project.id) do
      [first | _] ->
        push_navigate(socket, to: project_path(scope, "/pages/#{first.slug}/edit"))

      [] ->
        create_and_redirect(socket, scope)
    end
  end

  defp create_and_redirect(socket, scope) do
    attrs = %{
      title: "Untitled",
      organization_id: scope.project.organization_id,
      project_id: scope.project.id,
      user_id: scope.user.id
    }

    case Pages.create_page(attrs) do
      {:ok, page} ->
        push_navigate(socket, to: project_path(scope, "/pages/#{page.slug}/edit"))

      {:error, _} ->
        socket
        |> put_flash(:error, "Failed to create page")
        |> push_navigate(to: project_path(scope, "/"))
    end
  end
end
