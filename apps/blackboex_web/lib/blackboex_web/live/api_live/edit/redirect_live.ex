defmodule BlackboexWeb.ApiLive.Edit.RedirectLive do
  @moduledoc """
  Redirects bare /apis/:id/edit to /apis/:id/edit/chat.
  """

  use BlackboexWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    case {params["api_slug"], scope.project, params["id"]} do
      {api_slug, %{slug: proj_slug}, _} when not is_nil(api_slug) ->
        org_slug = scope.organization.slug

        {:ok,
         push_navigate(socket,
           to: "/orgs/#{org_slug}/projects/#{proj_slug}/apis/#{api_slug}/edit/chat"
         )}

      {_, _, id} when not is_nil(id) ->
        org_param = if params["org"], do: "?org=#{params["org"]}", else: ""
        {:ok, push_navigate(socket, to: "/apis/#{id}/edit/chat#{org_param}")}

      _ ->
        {:ok,
         push_navigate(socket,
           to: ~p"/apis"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H""
  end
end
