defmodule BlackboexWeb.FlowLive.ExecutionShow do
  @moduledoc """
  LiveView showing a single flow execution with node-by-node timeline.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
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
         page_title: "Execution — #{flow.name}"
       )}
    else
      nil -> {:ok, push_navigate(socket, to: ~p"/flows")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        <div class="flex items-center gap-2">
          <.link
            navigate={~p"/flows/#{@flow.id}/executions"}
            class="text-muted-foreground hover:text-foreground"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          Execution Details
        </div>
        <:subtitle>{@flow.name}</:subtitle>
      </.header>

      <%!-- Execution Summary --%>
      <.card class="p-4">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
          <div>
            <div class="text-muted-foreground text-xs mb-1">Status</div>
            <.badge class={exec_status_classes(@execution.status)}>{@execution.status}</.badge>
          </div>
          <div>
            <div class="text-muted-foreground text-xs mb-1">Duration</div>
            <span class="font-mono">{format_duration(@execution.duration_ms)}</span>
          </div>
          <div>
            <div class="text-muted-foreground text-xs mb-1">Started</div>
            <span>{format_time(@execution.inserted_at)}</span>
          </div>
          <div>
            <div class="text-muted-foreground text-xs mb-1">Finished</div>
            <span>{format_time(@execution.finished_at)}</span>
          </div>
        </div>

        <div
          :if={@execution.error}
          class="mt-4 rounded-md border border-destructive bg-destructive/10 p-3"
        >
          <div class="text-xs font-medium text-destructive mb-1">Error</div>
          <pre class="text-xs text-destructive whitespace-pre-wrap">{@execution.error}</pre>
        </div>

        <div
          :if={@execution.status == "halted" && @execution.wait_event_type}
          class="mt-4 rounded-md border border-amber-300 bg-amber-50 dark:bg-amber-950/20 p-3"
        >
          <div class="text-xs font-medium text-amber-800 dark:text-amber-200 mb-1">
            Waiting for Event
          </div>
          <div class="text-xs text-amber-700 dark:text-amber-300 space-y-1">
            <div>
              Event type: <span class="font-mono font-medium">{@execution.wait_event_type}</span>
            </div>
            <div>
              Resume URL:
              <code class="font-mono bg-amber-100 dark:bg-amber-900/50 px-1 rounded">
                POST /webhook/{@flow.webhook_token}/resume/{@execution.wait_event_type}
              </code>
            </div>
          </div>
        </div>
      </.card>

      <%!-- Node Timeline --%>
      <div>
        <h3 class="text-sm font-semibold mb-3">Node Timeline</h3>
        <div class="space-y-2">
          <.card :for={ne <- @node_executions} class="p-3">
            <div class="flex items-center justify-between gap-4">
              <div class="flex items-center gap-3 min-w-0">
                <div class={"size-2 rounded-full shrink-0 #{node_dot_color(ne.status)}"} />
                <div class="min-w-0">
                  <div class="text-sm font-medium">{ne.node_id}</div>
                  <div class="text-xs text-muted-foreground">{ne.node_type}</div>
                </div>
              </div>
              <div class="flex items-center gap-3 shrink-0">
                <.badge class={exec_status_classes(ne.status)}>{ne.status}</.badge>
                <span class="text-xs font-mono text-muted-foreground">
                  {format_duration(ne.duration_ms)}
                </span>
              </div>
            </div>

            <div :if={ne.error} class="mt-2 text-xs text-destructive bg-destructive/10 rounded p-2">
              {ne.error}
            </div>
          </.card>
        </div>
      </div>

      <%!-- Input / Output --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.card class="p-4">
          <h3 class="text-sm font-semibold mb-2">Input</h3>
          <pre class="text-xs font-mono bg-muted/50 rounded p-3 overflow-auto max-h-64 whitespace-pre-wrap">{format_json(@execution.input)}</pre>
        </.card>
        <.card class="p-4">
          <h3 class="text-sm font-semibold mb-2">Output</h3>
          <pre class="text-xs font-mono bg-muted/50 rounded p-3 overflow-auto max-h-64 whitespace-pre-wrap">{format_json(@execution.output)}</pre>
        </.card>
      </div>
    </div>
    """
  end

  defp exec_status_classes("completed"),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

  defp exec_status_classes("failed"),
    do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

  defp exec_status_classes("running"),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"

  defp exec_status_classes("halted"),
    do: "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200"

  defp exec_status_classes(_),
    do: "bg-muted text-muted-foreground"

  defp node_dot_color("completed"), do: "bg-green-500"
  defp node_dot_color("failed"), do: "bg-red-500"
  defp node_dot_color("running"), do: "bg-blue-500"
  defp node_dot_color("halted"), do: "bg-amber-500"
  defp node_dot_color(_), do: "bg-gray-400"

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
