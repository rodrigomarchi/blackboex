defmodule BlackboexWeb.FlowLive.ExecutionShow do
  @moduledoc """
  LiveView showing a single flow execution with node-by-node timeline.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Card

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
            class="text-muted-foreground hover:text-foreground"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <h1 class="text-sm font-semibold">Execution</h1>
          <span class="text-xs font-mono text-muted-foreground">
            {short_id(@execution.id)}
          </span>
          <span class="text-xs text-muted-foreground">{@flow.name}</span>
        </div>
      </header>

      <div class="flex-1 overflow-y-auto p-6 space-y-5">

      <%!-- Summary bar --%>
      <div class="flex flex-wrap items-center gap-3 text-sm">
        <div class={"inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium #{status_badge(@execution.status)}"}>
          <.icon name={status_icon(@execution.status)} class="size-3.5" />
          {@execution.status}
        </div>
        <div class="flex items-center gap-1.5 rounded-lg border bg-card px-3 py-1.5 text-muted-foreground">
          <.icon name="hero-clock-mini" class="size-3.5" />
          <span class="text-xs font-mono">{format_duration(@execution.duration_ms)}</span>
        </div>
        <div class="flex items-center gap-1.5 rounded-lg border bg-card px-3 py-1.5 text-muted-foreground">
          <.icon name="hero-play-mini" class="size-3.5 text-green-500" />
          <span class="text-xs">{format_time(@execution.inserted_at)}</span>
        </div>
        <div class="flex items-center gap-1.5 rounded-lg border bg-card px-3 py-1.5 text-muted-foreground">
          <.icon name="hero-stop-mini" class="size-3.5 text-red-400" />
          <span class="text-xs">{format_time(@execution.finished_at)}</span>
        </div>
        <div class="flex items-center gap-1.5 rounded-lg border bg-card px-3 py-1.5 text-muted-foreground">
          <.icon name="hero-squares-2x2-mini" class="size-3.5 text-blue-400" />
          <span class="text-xs">{length(@node_executions)} nodes</span>
        </div>
      </div>

      <%!-- Error banner --%>
      <div
        :if={@execution.error}
        class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-2.5"
      >
        <.icon name="hero-exclamation-triangle-mini" class="size-4 text-destructive shrink-0 mt-0.5" />
        <pre class="text-xs text-destructive whitespace-pre-wrap flex-1">{@execution.error}</pre>
      </div>

      <%!-- Halted banner --%>
      <div
        :if={@execution.status == "halted" && @execution.wait_event_type}
        class="flex items-start gap-2 rounded-lg border border-amber-300/50 dark:border-amber-700/50 bg-amber-50 dark:bg-amber-950/20 px-3 py-2.5"
      >
        <.icon
          name="hero-pause-circle-mini"
          class="size-4 text-amber-600 dark:text-amber-400 shrink-0 mt-0.5"
        />
        <div class="text-xs space-y-1">
          <div class="font-medium text-amber-800 dark:text-amber-200">
            Waiting for: <span class="font-mono">{@execution.wait_event_type}</span>
          </div>
          <code class="text-[11px] font-mono text-amber-700 dark:text-amber-300 bg-amber-100 dark:bg-amber-900/40 px-1.5 py-0.5 rounded">
            POST /webhook/{@flow.webhook_token}/resume/{@execution.wait_event_type}
          </code>
        </div>
      </div>

      <%!-- Input / Output --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.card>
          <.card_header class="py-2.5 px-4">
            <.card_title class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground uppercase tracking-wider">
              <.icon name="hero-arrow-down-on-square-mini" class="size-3.5 text-blue-400" />
              Input
            </.card_title>
          </.card_header>
          <.card_content class="pt-0 px-4 pb-3">
            <div
              id="exec-input-json"
              phx-hook="CodeEditor"
              phx-update="ignore"
              data-language="json"
              data-readonly="true"
              data-value={format_json(@execution.input)}
              class="w-full rounded-lg border overflow-hidden"
              style="max-height: 240px;"
            />
          </.card_content>
        </.card>
        <.card>
          <.card_header class="py-2.5 px-4">
            <.card_title class="flex items-center gap-1.5 text-xs font-medium text-muted-foreground uppercase tracking-wider">
              <.icon name="hero-arrow-up-on-square-mini" class="size-3.5 text-green-400" />
              Output
            </.card_title>
          </.card_header>
          <.card_content class="pt-0 px-4 pb-3">
            <div
              id="exec-output-json"
              phx-hook="CodeEditor"
              phx-update="ignore"
              data-language="json"
              data-readonly="true"
              data-value={format_json(@execution.output)}
              class="w-full rounded-lg border overflow-hidden"
              style="max-height: 240px;"
            />
          </.card_content>
        </.card>
      </div>

      <%!-- Node Timeline — compact table --%>
      <.card>
        <.card_header class="py-3 px-4">
          <.card_title class="flex items-center gap-2 text-sm">
            <.icon name="hero-queue-list" class="size-4 text-muted-foreground" />
            Node Timeline
          </.card_title>
        </.card_header>
        <.card_content class="p-0">
          <div class="divide-y">
            <div :for={ne <- @node_executions}>
              <% meta = node_icon(ne.node_type) %>
              <button
                type="button"
                class={"w-full flex items-center gap-3 px-4 py-2.5 text-left hover:bg-muted/30 transition-colors #{if @expanded_node == ne.node_id, do: "bg-muted/20", else: ""}"}
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
                    class="text-[11px] px-1.5 py-0.5 rounded font-medium"
                    style={"background: #{meta.color}15; color: #{meta.color};"}
                  >
                    {meta.label}
                  </span>
                </div>
                <div class="flex items-center gap-1.5">
                  <div class={"size-1.5 rounded-full #{status_dot(ne.status)}"} />
                  <span class={"text-xs #{status_text(ne.status)}"}>{ne.status}</span>
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
              </button>
              <div
                :if={@expanded_node == ne.node_id}
                class="px-4 pb-3 pt-1 pl-10 bg-muted/10 space-y-2"
              >
                <div
                  :if={ne.error}
                  class="text-xs text-destructive bg-destructive/10 rounded px-2 py-1.5"
                >
                  {ne.error}
                </div>
                <div :if={ne.output} class="text-xs">
                  <span class="text-muted-foreground font-medium">Output:</span>
                  <div
                    id={"node-output-#{ne.node_id}"}
                    phx-hook="CodeEditor"
                    phx-update="ignore"
                    data-language="json"
                    data-readonly="true"
                    data-value={format_json(ne.output)}
                    class="mt-1 w-full rounded-lg border overflow-hidden"
                    style="max-height: 160px;"
                  />
                </div>
                <div class="flex gap-4 text-[11px] text-muted-foreground">
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

  defp node_icon(type), do: Map.get(@node_type_meta, type, %{icon: "hero-cube", color: "#6b7280", label: type})

  defp status_badge("completed"), do: "bg-green-500/15 text-green-700 dark:text-green-400"
  defp status_badge("failed"), do: "bg-red-500/15 text-red-700 dark:text-red-400"
  defp status_badge("running"), do: "bg-blue-500/15 text-blue-700 dark:text-blue-400"
  defp status_badge("halted"), do: "bg-amber-500/15 text-amber-700 dark:text-amber-400"
  defp status_badge(_), do: "bg-muted text-muted-foreground"

  defp status_icon("completed"), do: "hero-check-circle-mini"
  defp status_icon("failed"), do: "hero-x-circle-mini"
  defp status_icon("running"), do: "hero-arrow-path-mini"
  defp status_icon("halted"), do: "hero-pause-circle-mini"
  defp status_icon(_), do: "hero-question-mark-circle-mini"

  defp status_dot("completed"), do: "bg-green-500"
  defp status_dot("failed"), do: "bg-red-500"
  defp status_dot("running"), do: "bg-blue-500 animate-pulse"
  defp status_dot("halted"), do: "bg-amber-500"
  defp status_dot(_), do: "bg-gray-400"

  defp status_text("completed"), do: "text-green-700 dark:text-green-400"
  defp status_text("failed"), do: "text-red-700 dark:text-red-400"
  defp status_text("running"), do: "text-blue-700 dark:text-blue-400"
  defp status_text("halted"), do: "text-amber-700 dark:text-amber-400"
  defp status_text(_), do: "text-muted-foreground"

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: "—"

  defp format_duration(nil), do: "—"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp format_time(nil), do: "—"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp format_json(nil), do: "—"

  defp format_json(data) do
    Jason.encode!(data, pretty: true)
  end
end
