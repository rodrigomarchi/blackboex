defmodule BlackboexWeb.ApiLive.Edit.RedirectLive do
  @moduledoc """
  Redirects bare /apis/:id/edit to /apis/:id/edit/chat.
  """

  use BlackboexWeb, :live_view

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    org_param = if params["org"], do: "?org=#{params["org"]}", else: ""
    {:ok, push_navigate(socket, to: "/apis/#{id}/edit/chat#{org_param}")}
  end

  @impl true
  def render(assigns) do
    ~H""
  end
end
