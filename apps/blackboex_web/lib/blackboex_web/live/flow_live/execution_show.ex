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
    <div class="space-y-5">
      <%!-- Header --%>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <.link navigate={~p"/flows"} class="shrink-0">
            <.logo_icon class="size-7" />
          </.link>
          <div class="h-6 w-px bg-border" />
          <.link
            navigate={~p"/flows/#{@flow.id}/executions"}
            class="inline-flex items-center justify-center rounded-md border border-border bg-card p-1.5 text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
          >
            <.icon name="hero-arrow-left" class="size-4" />
          </.link>
          <div>
            <div class="flex items-center gap-2">
              <h1 class="text-lg font-semibold">Execution</h1>
              <span class="text-xs font-mono text-muted-foreground">
                {short_id(@execution.id)}
              </span>
            </div>
            <p class="text-sm text-muted-foreground">{@flow.name}</p>
          </div>
        </div>
      </div>

      <%!-- Summary bar --%>
      <.card>
        <.card_content class="py-3 px-4">
          <div class="flex flex-wrap items-center gap-x-6 gap-y-2 text-sm">
            <div class="flex items-center gap-2">
              <div class={"size-2 rounded-full #{status_dot(@execution.status)}"} />
              <span class={"font-medium #{status_text(@execution.status)}"}>
                {@execution.status}
              </span>
            </div>
            <div class="flex items-center gap-1.5 text-muted-foreground">
              <.icon name="hero-clock-mini" class="size-3.5" />
              <span class="font-mono">{format_duration(@execution.duration_ms)}</span>
            </div>
            <div class="flex items-center gap-1.5 text-muted-foreground">
              <.icon name="hero-play-mini" class="size-3.5" />
              <span>{format_time(@execution.inserted_at)}</span>
            </div>
            <div class="flex items-center gap-1.5 text-muted-foreground">
              <.icon name="hero-stop-mini" class="size-3.5" />
              <span>{format_time(@execution.finished_at)}</span>
            </div>
            <div class="flex items-center gap-1.5 text-muted-foreground">
              <.icon name="hero-squares-2x2-mini" class="size-3.5" />
              <span>{length(@node_executions)} nodes</span>
            </div>
          </div>
        </.card_content>
      </.card>

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

      <%!-- Node Timeline — compact table --%>
      <.card>
        <.card_header class="py-3 px-4">
          <.card_title class="text-sm">Node Timeline</.card_title>
        </.card_header>
        <.card_content class="p-0">
          <div class="divide-y">
            <div :for={ne <- @node_executions}>
              <button
                type="button"
                class={"w-full flex items-center gap-3 px-4 py-2 text-left hover:bg-muted/30 transition-colors #{if @expanded_node == ne.node_id, do: "bg-muted/20", else: ""}"}
                phx-click="toggle_node"
                phx-value-node-id={ne.node_id}
              >
                <%!-- Timeline dot + connector --%>
                <div class="flex flex-col items-center shrink-0">
                  <div class={"size-2 rounded-full #{status_dot(ne.status)}"} />
                </div>
                <%!-- Node info --%>
                <div class="flex-1 min-w-0 flex items-center gap-2">
                  <span class="text-sm font-medium">{ne.node_id}</span>
                  <span class="text-[11px] text-muted-foreground px-1.5 py-0.5 rounded bg-muted/50">
                    {ne.node_type}
                  </span>
                </div>
                <%!-- Right side: status + duration --%>
                <span class={"text-xs #{status_text(ne.status)}"}>{ne.status}</span>
                <span class="text-xs font-mono text-muted-foreground w-12 text-right">
                  {format_duration(ne.duration_ms)}
                </span>
                <.icon
                  name={if @expanded_node == ne.node_id, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
                  class="size-3.5 text-muted-foreground/50 shrink-0"
                />
              </button>
              <%!-- Expanded details --%>
              <div
                :if={@expanded_node == ne.node_id}
                class="px-4 pb-3 pt-1 pl-10 bg-muted/10 space-y-2"
              >
                <div :if={ne.error} class="text-xs text-destructive bg-destructive/10 rounded px-2 py-1.5">
                  {ne.error}
                </div>
                <div :if={ne.output} class="text-xs">
                  <span class="text-muted-foreground font-medium">Output:</span>
                  <pre class="mt-1 font-mono bg-muted/40 rounded px-2 py-1.5 overflow-auto max-h-32 whitespace-pre-wrap">{format_json(ne.output)}</pre>
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

      <%!-- Input / Output --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.card>
          <.card_header class="py-2.5 px-4">
            <.card_title class="text-xs font-medium text-muted-foreground uppercase tracking-wider">
              Input
            </.card_title>
          </.card_header>
          <.card_content class="pt-0 px-4 pb-3">
            <pre class="text-xs font-mono bg-muted/30 rounded-md p-3 overflow-auto max-h-48 whitespace-pre-wrap border">{format_json(@execution.input)}</pre>
          </.card_content>
        </.card>
        <.card>
          <.card_header class="py-2.5 px-4">
            <.card_title class="text-xs font-medium text-muted-foreground uppercase tracking-wider">
              Output
            </.card_title>
          </.card_header>
          <.card_content class="pt-0 px-4 pb-3">
            <pre class="text-xs font-mono bg-muted/30 rounded-md p-3 overflow-auto max-h-48 whitespace-pre-wrap border">{format_json(@execution.output)}</pre>
          </.card_content>
        </.card>
      </div>
    </div>
    """
  end

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
