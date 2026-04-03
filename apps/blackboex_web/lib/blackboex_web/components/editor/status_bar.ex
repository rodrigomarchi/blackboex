defmodule BlackboexWeb.Components.Editor.StatusBar do
  @moduledoc """
  Status bar displayed at the bottom of the editor page.
  Shows language, version number, and compilation status.
  """
  use BlackboexWeb, :html

  attr :api, :map, required: true
  attr :versions, :list, default: []
  attr :selected_version, :map, default: nil

  @spec status_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def status_bar(assigns) do
    assigns = assign(assigns, :latest_version, List.first(assigns.versions))

    ~H"""
    <div class="flex h-6 shrink-0 items-center border-t bg-card px-3 text-[11px] text-muted-foreground gap-3">
      <span>Elixir</span>
      <span class="opacity-30">│</span>
      <span :if={@latest_version}>v{@latest_version.version_number}</span>
      <span :if={!@latest_version}>no versions</span>
      <span class="opacity-30">│</span>
      <span class={status_text_color(@api.status)}>{@api.status}</span>
      <%= if @selected_version do %>
        <span class="opacity-30">│</span>
        <span class="text-info-foreground">viewing v{@selected_version.version_number}</span>
        <button phx-click="clear_version_view" class="text-primary hover:underline ml-1">
          ← current
        </button>
      <% end %>
    </div>
    """
  end

  defp status_text_color(status), do: api_status_classes(status)
end
