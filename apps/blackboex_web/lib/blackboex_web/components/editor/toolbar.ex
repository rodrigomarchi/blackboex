defmodule BlackboexWeb.Components.Editor.Toolbar do
  @moduledoc """
  Compact toolbar for the API code editor page.
  Shows API name, status, save actions, and command palette trigger.
  """
  use BlackboexWeb, :html

  import BlackboexWeb.Components.Badge

  attr :api, :map, required: true
  attr :selected_version, :map, default: nil
  attr :generation_status, :string, default: nil

  @spec editor_toolbar(map()) :: Phoenix.LiveView.Rendered.t()
  def editor_toolbar(assigns) do
    ~H"""
    <header class="flex h-12 shrink-0 items-center border-b bg-card px-4 gap-3">
      <.link
        navigate={~p"/apis"}
        class="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-accent"
        title="Back to APIs"
      >
        <.icon name="hero-arrow-left" class="size-4" />
      </.link>

      <h1 class="text-sm font-semibold truncate max-w-[200px]">{@api.name}</h1>

      <.badge size="xs" variant="status" class={status_color(@api.status)}>
        {@api.status}
      </.badge>

      <.badge
        :if={@selected_version}
        size="xs"
        variant="info"
      >
        v{@selected_version.version_number}
      </.badge>

      <.badge
        :if={@generation_status in ~w(pending generating validating)}
        size="xs"
        variant="warning"
        class="animate-pulse"
      >
        <.icon name="hero-arrow-path" class="size-3 animate-spin" /> generating
      </.badge>

      <.badge
        :if={@generation_status == "failed"}
        size="xs"
        variant="destructive"
      >
        generation failed
      </.badge>

      <div class="flex-1" />

      <%!-- Command palette trigger --%>
      <.button
        variant="outline"
        phx-click="toggle_command_palette"
        class="h-auto inline-flex items-center gap-1 rounded-md px-2 py-1 text-muted-caption hover:text-foreground hover:bg-accent"
        title="Command Palette (⌘K)"
      >
        <.icon name="hero-command-line" class="size-3.5 text-accent-violet" />
        <kbd class="hidden md:inline text-2xs font-mono">⌘K</kbd>
      </.button>
    </header>
    """
  end

  defp status_color(status), do: api_status_border(status)
end
