defmodule BlackboexWeb.ApiLive.Show do
  @moduledoc """
  Redirects to the editor. Kept for backward compatibility.
  """

  use BlackboexWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    to =
      case {params["api_slug"], scope.project, params["id"]} do
        {api_slug, %{slug: proj_slug}, _}
        when not is_nil(api_slug) and not is_nil(scope.organization) ->
          "/orgs/#{scope.organization.slug}/projects/#{proj_slug}/apis/#{api_slug}/edit/chat"

        {_, _, id} when not is_nil(id) ->
          ~p"/apis/#{id}/edit"

        _ ->
          ~p"/apis"
      end

    {:ok, push_navigate(socket, to: to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div></div>
    """
  end
end
