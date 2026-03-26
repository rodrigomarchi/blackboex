defmodule BlackboexWeb.ApiLive.New do
  @moduledoc """
  Redirects to the API index page where creation now happens via modal.
  Kept for backward compatibility with bookmarked URLs.
  """

  use BlackboexWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/apis")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div></div>
    """
  end
end
