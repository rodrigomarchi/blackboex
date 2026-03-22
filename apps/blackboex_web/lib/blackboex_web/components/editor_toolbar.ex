defmodule BlackboexWeb.Components.EditorToolbar do
  @moduledoc """
  Compact toolbar for the API code editor page.
  Shows API name, status, save actions, and panel toggle buttons.
  """
  use BlackboexWeb, :html

  attr :api, :map, required: true
  attr :code, :string, required: true
  attr :saving, :boolean, default: false
  attr :right_panel, :atom, default: nil
  attr :bottom_panel_open, :boolean, default: false
  attr :selected_version, :map, default: nil

  @spec editor_toolbar(map()) :: Phoenix.LiveView.Rendered.t()
  def editor_toolbar(assigns) do
    ~H"""
    <header class="flex h-11 shrink-0 items-center border-b bg-card px-3 gap-2">
      <.link
        navigate={~p"/apis/#{@api.id}"}
        class="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-accent"
        title="Voltar"
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
        :if={@code != (@api.source_code || "")}
        class="inline-flex items-center rounded-full bg-amber-500/10 px-2 py-0.5 text-[10px] font-medium text-amber-600"
      >
        unsaved
      </span>

      <span
        :if={@selected_version}
        class="inline-flex items-center rounded-full bg-blue-500/10 px-2 py-0.5 text-[10px] font-medium text-blue-600"
      >
        v{@selected_version.version_number}
      </span>

      <div class="flex-1" />

      <%!-- Panel toggle buttons --%>
      <div class="flex items-center gap-0.5 rounded-lg border p-0.5">
        <button
          phx-click="toggle_chat"
          class={panel_btn_class(@right_panel == :chat)}
          title="Chat (⌘L)"
        >
          <.icon name="hero-chat-bubble-left-right" class="size-3.5" />
          <span class="hidden md:inline ml-1">Chat</span>
        </button>
        <button
          phx-click="toggle_bottom_panel"
          class={panel_btn_class(@bottom_panel_open)}
          title="Testing (⌘J)"
        >
          <.icon name="hero-beaker" class="size-3.5" />
          <span class="hidden md:inline ml-1">Test</span>
        </button>
        <button
          phx-click="toggle_config"
          class={panel_btn_class(@right_panel == :config)}
          title="Configurações (⌘I)"
        >
          <.icon name="hero-cog-6-tooth" class="size-3.5" />
          <span class="hidden md:inline ml-1">Config</span>
        </button>
      </div>

      <div class="h-4 w-px bg-border" />

      <%!-- Save button (Save = Compile + Validate) --%>
      <button
        phx-click="save"
        disabled={@saving}
        class="inline-flex items-center rounded-md bg-primary px-2.5 py-1 text-xs font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
      >
        <.icon name="hero-bolt" class="size-3 mr-1" /> Save
      </button>

      <div class="h-4 w-px bg-border" />

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

  defp panel_btn_class(active?) do
    base = "rounded px-2 py-1 text-xs font-medium transition-colors inline-flex items-center"

    if active?,
      do: "#{base} bg-primary text-primary-foreground",
      else: "#{base} text-muted-foreground hover:text-foreground hover:bg-base-200"
  end

  defp status_color("draft"), do: "border bg-muted text-muted-foreground"
  defp status_color("compiled"), do: "border-green-500 bg-green-50 text-green-700"
  defp status_color("published"), do: "border-blue-500 bg-blue-50 text-blue-700"
  defp status_color("archived"), do: "border-gray-500 bg-gray-50 text-gray-500"
  defp status_color(_), do: "border bg-muted text-muted-foreground"
end
