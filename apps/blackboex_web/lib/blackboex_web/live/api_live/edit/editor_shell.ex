defmodule BlackboexWeb.ApiLive.Edit.EditorShell do
  @moduledoc """
  Shared shell component for all Edit tab LiveViews.
  Renders toolbar + tab bar + content slot + status bar + command palette.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Editor.Toolbar
  import BlackboexWeb.Components.Editor.StatusBar
  import BlackboexWeb.Components.Editor.CommandPalette
  import BlackboexWeb.ApiLive.Edit.Helpers, only: [test_summary_class: 1]

  attr :api, :map, required: true
  attr :active_tab, :string, required: true
  attr :versions, :list, default: []
  attr :selected_version, :map, default: nil
  attr :generation_status, :string, default: nil
  attr :validation_report, :map, default: nil
  attr :test_summary, :string, default: nil
  attr :command_palette_open, :boolean, default: false
  attr :command_palette_query, :string, default: ""
  attr :command_palette_selected, :integer, default: 0
  slot :inner_block, required: true

  @tabs [
    %{id: "chat", label: "Chat"},
    %{id: "code", label: "Code"},
    %{id: "tests", label: "Tests"},
    %{id: "validation", label: "Validation"},
    %{id: "docs", label: "Docs"},
    %{id: "versions", label: "Versions"},
    %{id: "run", label: "Run"},
    %{id: "metrics", label: "Metrics"},
    %{id: "keys", label: "API Keys"},
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
                "px-3 py-1.5 text-xs font-medium border-b-2 transition-colors",
                if(tab.id == @active_tab,
                  do: "border-primary text-primary",
                  else: "border-transparent text-muted-foreground hover:text-foreground"
                )
              ]}
            >
              {tab.label}
              <span
                :if={tab.id == "tests" && @test_summary}
                class={[
                  "ml-1 inline-flex rounded-full px-1.5 text-[10px] font-semibold",
                  test_summary_class(@test_summary)
                ]}
              >
                {@test_summary}
              </span>
              <span
                :if={tab.id == "validation" && @validation_report}
                class={[
                  "ml-1 inline-flex rounded-full px-1.5 text-[10px] font-semibold",
                  if(@validation_report.overall == :pass,
                    do: "bg-success/10 text-success-foreground",
                    else: "bg-destructive/10 text-destructive"
                  )
                ]}
              >
                {if @validation_report.overall == :pass, do: "✓", else: "!"}
              </span>
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
end
