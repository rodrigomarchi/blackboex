defmodule BlackboexWeb.Hooks.TrackCurrentPath do
  @moduledoc """
  LiveView on_mount hook that tracks the current URL path in assigns.

  Sets `current_path` on every `handle_params` callback so the sidebar
  can highlight the active navigation item.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, nil)
      |> attach_hook(:track_url, :handle_params, fn _params, url, socket ->
        {:cont, assign(socket, :current_path, URI.parse(url).path)}
      end)

    {:cont, socket}
  end
end
