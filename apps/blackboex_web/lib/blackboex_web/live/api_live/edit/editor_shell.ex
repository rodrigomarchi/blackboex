defmodule BlackboexWeb.ApiLive.Edit.EditorShell do
  @moduledoc """
  Shared shell component for all Edit tab LiveViews.
  Renders toolbar + tab bar + content slot + status bar + command palette.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Editor.Toolbar
  import BlackboexWeb.Components.Editor.StatusBar
  import BlackboexWeb.Components.Editor.CommandPalette
  attr :api, :map, required: true
  attr :active_tab, :string, required: true
  attr :versions, :list, default: []
  attr :selected_version, :map, default: nil
  attr :generation_status, :string, default: nil
  attr :validation_report, :map, default: nil
  attr :command_palette_open, :boolean, default: false
  attr :command_palette_query, :string, default: ""
  attr :command_palette_selected, :integer, default: 0
  slot :inner_block, required: true

  @tabs [
    %{id: "chat", label: "Chat"},
    %{id: "validation", label: "Validation"},
    %{id: "run", label: "Run"},
    %{id: "metrics", label: "Metrics"},
    %{id: "publish", label: "Publish"},
    %{id: "info", label: "Info"}
  ]

  @spec editor_shell(map()) :: Phoenix.LiveView.Rendered.t()
  def editor_shell(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div class="flex flex-col h-full" id="editor-root" phx-hook="KeyboardShortcuts">
      <.editor_toolbar
        api={@api}
        selected_version={@selected_version}
        generation_status={@generation_status}
      />

      <div class="flex flex-1 min-h-0">
        <div class="flex flex-col flex-1 min-w-0">
          <%!-- Tab Bar --%>
          <div class="flex items-center border-b px-2 shrink-0 bg-card">
            <.link
              :for={tab <- @tabs}
              navigate={"/apis/#{@api.id}/edit/#{tab.id}"}
              class={[
                "flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border-b-2 transition-colors",
                if(tab.id == @active_tab,
                  do: "border-primary text-primary",
                  else: "border-transparent text-muted-foreground hover:text-foreground"
                )
              ]}
            >
              <.icon name={tab_icon(tab.id)} class={"size-3.5 #{tab_icon_color(tab.id)}"} />
              {tab.label}
              <.badge
                :if={tab.id == "validation" && @validation_report}
                size="xs"
                variant="status"
                class={
                  "ml-1 " <>
                    if(@validation_report.overall == :pass,
                      do: "bg-success/10 text-success-foreground",
                      else: "bg-destructive/10 text-destructive"
                    )
                }
              >
                {if @validation_report.overall == :pass, do: "✓", else: "!"}
              </.badge>
            </.link>
          </div>

          <%!-- Content Area --%>
          <div class="flex-1 min-h-0 relative overflow-hidden">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>

      <.status_bar api={@api} versions={@versions} selected_version={@selected_version} />

      <.command_palette
        open={@command_palette_open}
        query={@command_palette_query}
        api={@api}
        selected_index={@command_palette_selected}
      />
    </div>
    """
  end

  defp tab_icon("chat"), do: "hero-chat-bubble-left-right"
  defp tab_icon("validation"), do: "hero-shield-check"
  defp tab_icon("run"), do: "hero-play"
  defp tab_icon("metrics"), do: "hero-chart-bar"
  defp tab_icon("publish"), do: "hero-rocket-launch"
  defp tab_icon("info"), do: "hero-information-circle"
  defp tab_icon(_), do: "hero-squares-2x2"

  defp tab_icon_color("chat"), do: "text-accent-violet"
  defp tab_icon_color("validation"), do: "text-accent-teal"
  defp tab_icon_color("run"), do: "text-accent-emerald"
  defp tab_icon_color("metrics"), do: "text-accent-sky"
  defp tab_icon_color("publish"), do: "text-accent-emerald"
  defp tab_icon_color("info"), do: "text-accent-blue"
  defp tab_icon_color(_), do: "text-muted-foreground"
end
