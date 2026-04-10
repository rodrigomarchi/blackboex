defmodule BlackboexWeb.Components.FlowEditor.FlowHeader do
  @moduledoc """
  Top header bar for the flow editor.
  Shows flow name, status, webhook URL, and action buttons.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.UI.SectionHeading

  attr :flow, :map, required: true
  attr :saving, :boolean, default: false
  attr :saved, :boolean, default: false

  def flow_header(assigns) do
    ~H"""
    <header class="flex h-12 shrink-0 items-center justify-between border-b bg-card px-4">
      <div class="flex items-center gap-3">
        <.link navigate={~p"/"} class="text-foreground hover:text-foreground/80">
          <.logo_icon class="size-7" />
        </.link>
        <.link navigate={~p"/flows"} class="text-muted-foreground hover:text-foreground">
          <.icon name="hero-arrow-left" class="size-5" />
        </.link>
        <.section_heading level="h1" class="text-sm font-semibold truncate max-w-xs">
          {@flow.name}
        </.section_heading>
        <%= if @flow.status == "active" do %>
          <span class="inline-flex items-center gap-1.5 rounded-full bg-status-completed/15 px-2.5 py-0.5 text-xs font-medium text-status-completed-foreground">
            <span class="size-1.5 rounded-full bg-status-completed animate-pulse" /> active
          </span>
          <.button
            variant="ghost"
            phx-click="deactivate_flow"
            class="h-auto inline-flex items-center gap-1 rounded-full bg-muted/50 px-2.5 py-1 text-xs text-muted-foreground hover:bg-accent-orange/15 hover:text-accent-orange transition-colors"
          >
            <.icon name="hero-pause-circle-mini" class="size-3.5" /> Pause
          </.button>
        <% else %>
          <span class="inline-flex items-center gap-1.5 rounded-full bg-muted px-2.5 py-0.5 text-xs font-medium text-muted-foreground">
            <span class="size-1.5 rounded-full bg-gray-400" /> draft
          </span>
          <.button
            variant="ghost"
            phx-click="activate_flow"
            class="h-auto inline-flex items-center gap-1 rounded-full bg-status-completed/15 px-2.5 py-1 text-xs text-status-completed-foreground hover:bg-status-completed/25 transition-colors"
          >
            <.icon name="hero-bolt-mini" class="size-3.5" /> Activate
          </.button>
        <% end %>
      </div>

      <div class="flex items-center gap-2">
        <%!-- Webhook URL --%>
        <div class="hidden md:flex items-center gap-1 rounded border bg-muted/50 px-2 py-1">
          <.icon name="hero-link-mini" class="size-3.5 text-accent-emerald shrink-0" />
          <span class="text-[0.65rem] text-muted-foreground font-mono truncate max-w-[200px]">
            /webhook/{String.slice(@flow.webhook_token, 0..7)}...
          </span>
          <.button
            variant="ghost"
            phx-click={JS.dispatch("phx:copy_to_clipboard", detail: %{text: webhook_url(@flow)})}
            class="h-auto w-auto p-0.5 text-muted-foreground hover:text-foreground hover:bg-transparent"
            title="Copy webhook URL"
          >
            <.icon name="hero-clipboard-document" class="size-3.5 text-accent-sky" />
          </.button>
          <.button
            variant="ghost"
            phx-click="request_confirm"
            phx-value-action="regenerate_token"
            class="h-auto w-auto p-0.5 text-muted-foreground hover:text-foreground hover:bg-transparent"
            title="Regenerate token"
          >
            <.icon name="hero-arrow-path" class="size-3.5 text-accent-amber" />
          </.button>
        </div>

        <span :if={@saved} class="text-xs text-success-foreground">Saved</span>

        <.button variant="outline" size="sm" navigate={~p"/flows/#{@flow.id}/executions"}>
          <.icon name="hero-clock" class="mr-1.5 size-4 text-accent-sky" /> History
        </.button>
        <.button variant="outline" size="sm" phx-click="open_run_modal">
          <.icon name="hero-play" class="mr-1.5 size-4 text-accent-emerald" /> Run
        </.button>
        <.button variant="outline" size="sm" phx-click="request_json_preview">
          <.icon name="hero-code-bracket" class="mr-1.5 size-4 text-accent-violet" /> JSON
        </.button>
        <.button
          variant="primary"
          size="sm"
          phx-click="request_save"
          disabled={@saving}
        >
          <%= if @saving do %>
            <.icon name="hero-arrow-path" class="mr-1.5 size-4 animate-spin" /> Saving...
          <% else %>
            <.icon name="hero-arrow-down-tray" class="mr-1.5 size-4 text-accent-emerald" /> Save
          <% end %>
        </.button>
      </div>
    </header>
    """
  end

  defp webhook_url(flow) do
    BlackboexWeb.Endpoint.url() <> "/webhook/#{flow.webhook_token}"
  end
end
