defmodule BlackboexWeb.ApiLive.Show do
  @moduledoc """
  Redirects to the editor. Kept for backward compatibility.
  """

  use BlackboexWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/apis/#{id}/edit")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div></div>
    """
  end
end
