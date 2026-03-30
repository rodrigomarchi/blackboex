defmodule BlackboexWeb.Components.EditorToolbar do
  @moduledoc """
  Compact toolbar for the API code editor page.
  Shows API name, status, save actions, and command palette trigger.
  """
  use BlackboexWeb, :html

  attr :api, :map, required: true
  attr :selected_version, :map, default: nil
  attr :generation_status, :string, default: nil

  @spec editor_toolbar(map()) :: Phoenix.LiveView.Rendered.t()
  def editor_toolbar(assigns) do
    ~H"""
    <header class="flex h-11 shrink-0 items-center border-b bg-card px-3 gap-2">
      <.link
        navigate={~p"/apis"}
        class="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-accent"
        title="Back to APIs"
      >
        <.icon name="hero-arrow-left" class="size-4" />
      </.link>

      <div class="h-4 w-px bg-border" />

      <h1 class="text-sm font-semibold truncate max-w-[200px]">{@api.name}</h1>

      <span class={[
        "inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold",
        status_color(@api.status)
      ]}>
        {@api.status}
      </span>

      <span
        :if={@selected_version}
        class="inline-flex items-center rounded-full bg-blue-500/10 px-2 py-0.5 text-[10px] font-medium text-blue-600"
      >
        v{@selected_version.version_number}
      </span>

      <span
        :if={@generation_status in ~w(pending generating validating)}
        class="inline-flex items-center gap-1 rounded-full bg-amber-500/10 px-2 py-0.5 text-[10px] font-medium text-amber-600 animate-pulse"
      >
        <.icon name="hero-arrow-path" class="size-3 animate-spin" /> generating
      </span>

      <span
        :if={@generation_status == "failed"}
        class="inline-flex items-center gap-1 rounded-full bg-destructive/10 px-2 py-0.5 text-[10px] font-medium text-destructive"
      >
        generation failed
      </span>

      <div class="flex-1" />

      <%!-- Command palette trigger --%>
      <button
        phx-click="toggle_command_palette"
        class="inline-flex items-center gap-1 rounded-md border px-2 py-1 text-xs text-muted-foreground hover:text-foreground hover:bg-accent"
        title="Command Palette (⌘K)"
      >
        <.icon name="hero-command-line" class="size-3.5" />
        <kbd class="hidden md:inline text-[10px] font-mono">⌘K</kbd>
      </button>
    </header>
    """
  end

  defp status_color("draft"), do: "border bg-muted text-muted-foreground"
  defp status_color("compiled"), do: "border-green-500 bg-green-50 text-green-700"
  defp status_color("published"), do: "border-blue-500 bg-blue-50 text-blue-700"
  defp status_color("archived"), do: "border-gray-500 bg-gray-50 text-gray-500"
  defp status_color(_), do: "border bg-muted text-muted-foreground"
end
