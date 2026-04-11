defmodule BlackboexWeb.FlowLive.ExecutionShow do
  @moduledoc """
  LiveView showing a single flow execution with node-by-node timeline.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Shared.CodeEditorField
  import BlackboexWeb.Components.Shared.InlineCode
  import BlackboexWeb.Components.Shared.StatChip
  import BlackboexWeb.Components.StatusHelpers
  import BlackboexWeb.Components.UI.AlertBanner
  import BlackboexWeb.FlowLive.ExecutionHelpers
  import BlackboexWeb.Components.UI.SectionHeading

  alias Blackboex.FlowExecutions
  alias Blackboex.Flows

  @impl true
  def mount(%{"id" => flow_id, "execution_id" => execution_id}, _session, socket) do
    org = socket.assigns.current_scope.organization

    with flow when not is_nil(flow) <- org && Flows.get_flow(org.id, flow_id),
         execution when not is_nil(execution) <-
           FlowExecutions.get_execution_for_org(org.id, execution_id) do
      node_execs =
        (execution.node_executions || [])
        |> Enum.sort_by(& &1.started_at, {:asc, DateTime})

      {:ok,
       assign(socket,
         flow: flow,
         execution: execution,
         node_executions: node_execs,
         expanded_node: nil,
         page_title: "Execution — #{flow.name}"
       )}
    else
      nil -> {:ok, push_navigate(socket, to: ~p"/flows")}
    end
  end

  @impl true
  def handle_event("toggle_node", %{"node-id" => node_id}, socket) do
    expanded =
      if socket.assigns.expanded_node == node_id, do: nil, else: node_id

    {:noreply, assign(socket, expanded_node: expanded)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen flex-col overflow-hidden">
      <header class="flex h-12 shrink-0 items-center border-b bg-card px-4">
        <div class="flex items-center gap-3">
          <.link navigate={~p"/"} class="text-foreground hover:text-foreground/80">
            <.logo_icon class="size-7" />
          </.link>
          <.link
            navigate={~p"/flows/#{@flow.id}/executions"}
            class="link-muted"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <.section_heading level="h2" compact>Execution</.section_heading>
          <span class="text-muted-caption font-mono">
            {short_id(@execution.id)}
          </span>
          <span class="text-muted-caption">{@flow.name}</span>
        </div>
      </header>

      <div class="flex-1 overflow-y-auto p-6 space-y-5">
        <%!-- Summary bar --%>
        <div class="flex flex-wrap items-center gap-3 text-sm">
          <.badge variant="status" class={"gap-1.5 #{status_badge(@execution.status)}"}>
            <.icon name={status_icon(@execution.status)} class="size-3.5" />
            {@execution.status}
          </.badge>
          <.stat_chip
            icon="hero-clock-mini"
            label="Duration"
            value={format_duration(@execution.duration_ms)}
          />
          <.stat_chip
            icon="hero-play-mini"
            icon_class="text-accent-emerald"
            label="Started"
            value={format_time(@execution.inserted_at)}
          />
          <.stat_chip
            icon="hero-stop-mini"
            icon_class="text-accent-red"
            label="Ended"
            value={format_time(@execution.finished_at)}
          />
          <.stat_chip
            icon="hero-squares-2x2-mini"
            icon_class="text-accent-blue"
            label="Nodes"
            value={length(@node_executions)}
          />
        </div>

        <%!-- Error banner --%>
        <.alert_banner
          :if={@execution.error}
          variant="destructive"
          icon="hero-exclamation-triangle-mini"
        >
          <.code_editor_field
            id="execution-error-viewer"
            value={@execution.error}
            max_height="max-h-40"
            class="flex-1"
          />
        </.alert_banner>

        <%!-- Halted banner --%>
        <.alert_banner
          :if={@execution.status == "halted" && @execution.wait_event_type}
          variant="warning"
          icon="hero-pause-circle-mini"
        >
          <div class="text-xs space-y-1">
            <div class="font-medium">
              Waiting for: <span class="font-mono">{@execution.wait_event_type}</span>
            </div>
            <.inline_code class="text-micro bg-warning/20">
              POST /webhook/{@flow.webhook_token}/resume/{@execution.wait_event_type}
            </.inline_code>
          </div>
        </.alert_banner>

        <%!-- Input / Output --%>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.card>
            <.card_header size="compact">
              <.card_title size="label" class="flex items-center gap-1.5">
                <.icon name="hero-arrow-down-on-square-mini" class="size-3.5 text-accent-blue" />
                Input
              </.card_title>
            </.card_header>
            <.card_content size="compact">
              <.code_editor_field
                id="exec-input-json"
                value={format_json(@execution.input)}
                max_height="max-h-[240px]"
                class="w-full rounded-lg"
              />
            </.card_content>
          </.card>
          <.card>
            <.card_header size="compact">
              <.card_title size="label" class="flex items-center gap-1.5">
                <.icon name="hero-arrow-up-on-square-mini" class="size-3.5 text-accent-emerald" />
                Output
              </.card_title>
            </.card_header>
            <.card_content size="compact">
              <.code_editor_field
                id="exec-output-json"
                value={format_json(@execution.output)}
                max_height="max-h-[240px]"
                class="w-full rounded-lg"
              />
            </.card_content>
          </.card>
        </div>

        <%!-- Node Timeline — compact table --%>
        <.card>
          <.card_header size="compact">
            <.card_title class="flex items-center gap-2 text-sm">
              <.icon name="hero-queue-list" class="size-4 text-accent-violet" /> Node Timeline
            </.card_title>
          </.card_header>
          <.card_content class="p-0">
            <div class="divide-y">
              <div :for={ne <- @node_executions}>
                <% meta = node_icon(ne.node_type) %>
                <.button
                  type="button"
                  variant="ghost"
                  size="list-item"
                  class={"flex items-center gap-3 hover:bg-muted/30 transition-colors #{if @expanded_node == ne.node_id, do: "bg-muted/20", else: ""}"}
                  phx-click="toggle_node"
                  phx-value-node-id={ne.node_id}
                >
                  <div
                    class="flex items-center justify-center size-7 rounded-lg shrink-0"
                    style={"background: #{meta.color}20; color: #{meta.color};"}
                  >
                    <.icon name={meta.icon} class="size-4" />
                  </div>
                  <div class="flex-1 min-w-0 flex items-center gap-2">
                    <span class="text-sm font-medium">{ne.node_id}</span>
                    <span
                      class="text-micro px-1.5 py-0.5 rounded font-medium"
                      style={"background: #{meta.color}15; color: #{meta.color};"}
                    >
                      {meta.label}
                    </span>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <div class={"size-1.5 rounded-full #{status_dot(ne.status)}"} />
                    <span class={"text-xs #{execution_status_text_class(ne.status)}"}>
                      {ne.status}
                    </span>
                  </div>
                  <span class="text-xs font-mono text-muted-foreground w-14 text-right">
                    {format_duration(ne.duration_ms)}
                  </span>
                  <.icon
                    name={
                      if @expanded_node == ne.node_id,
                        do: "hero-chevron-down-mini",
                        else: "hero-chevron-right-mini"
                    }
                    class="size-3.5 text-muted-foreground/50 shrink-0"
                  />
                </.button>
                <div
                  :if={@expanded_node == ne.node_id}
                  class="px-4 pb-3 pt-1 pl-10 bg-muted/10 space-y-2"
                >
                  <.alert_banner :if={ne.error} variant="destructive" class="py-1 px-2 text-xs">
                    {ne.error}
                  </.alert_banner>
                  <div :if={ne.output} class="text-xs">
                    <span class="text-muted-foreground font-medium">Output:</span>
                    <.code_editor_field
                      id={"node-output-#{ne.node_id}"}
                      value={format_json(ne.output)}
                      max_height="max-h-[160px]"
                      class="mt-1 w-full rounded-lg"
                    />
                  </div>
                  <div class="flex gap-4 text-micro text-muted-foreground">
                    <span :if={ne.started_at}>Started: {format_time(ne.started_at)}</span>
                    <span :if={ne.finished_at}>Finished: {format_time(ne.finished_at)}</span>
                  </div>
                </div>
              </div>
            </div>
          </.card_content>
        </.card>
      </div>
    </div>
    """
  end

  @node_type_meta %{
    "start" => %{icon: "hero-play", color: "#10b981", label: "Start"},
    "elixir_code" => %{icon: "hero-code-bracket", color: "#8b5cf6", label: "Elixir Code"},
    "condition" => %{icon: "hero-arrows-right-left", color: "#3b82f6", label: "Condition"},
    "end" => %{icon: "hero-stop", color: "#6b7280", label: "End"},
    "http_request" => %{icon: "hero-globe-alt", color: "#f97316", label: "HTTP Request"},
    "delay" => %{icon: "hero-clock", color: "#eab308", label: "Delay"},
    "webhook_wait" => %{icon: "hero-arrow-path", color: "#ec4899", label: "Webhook Wait"},
    "sub_flow" => %{icon: "hero-squares-2x2", color: "#6366f1", label: "Sub-Flow"},
    "for_each" => %{icon: "hero-arrow-path-rounded-square", color: "#14b8a6", label: "For Each"}
  }

  defp node_icon(type),
    do: Map.get(@node_type_meta, type, %{icon: "hero-cube", color: "#6b7280", label: type})

  defp status_dot(status), do: execution_status_dot(status)

  defp format_json(nil), do: "—"

  defp format_json(data) do
    Jason.encode!(data, pretty: true)
  end
end
