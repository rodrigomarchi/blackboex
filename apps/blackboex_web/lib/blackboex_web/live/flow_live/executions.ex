defmodule BlackboexWeb.FlowLive.Executions do
  @moduledoc """
  LiveView listing executions for a flow.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Shared.EmptyState

  alias Blackboex.FlowExecutions
  alias Blackboex.Flows

  @impl true
  def mount(%{"id" => flow_id}, _session, socket) do
    org = socket.assigns.current_scope.organization

    case org && Flows.get_flow(org.id, flow_id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/flows")}

      flow ->
        executions = FlowExecutions.list_executions_for_flow(flow.id)
        stats = compute_stats(executions)

        {:ok,
         assign(socket,
           flow: flow,
           executions: executions,
           stats: stats,
           page_title: "Executions — #{flow.name}"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen flex-col overflow-hidden">
      <header class="flex h-12 shrink-0 items-center justify-between border-b bg-card px-4">
        <div class="flex items-center gap-3">
          <.link navigate={~p"/"} class="text-foreground hover:text-foreground/80">
            <.logo_icon class="size-7" />
          </.link>
          <.link
            navigate={~p"/flows/#{@flow.id}/edit"}
            class="text-muted-foreground hover:text-foreground"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <h1 class="text-sm font-semibold">Executions</h1>
          <span class="text-xs text-muted-foreground">{@flow.name}</span>
        </div>
        <div :if={@executions != []} class="flex items-center gap-1.5 text-xs text-muted-foreground">
          <.icon name="hero-bolt-mini" class="size-3.5" />
          {length(@executions)} total runs
        </div>
      </header>

      <div class="flex-1 overflow-y-auto p-6 space-y-6">

      <%= if @executions != [] do %>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <.stat_mini label="Total" value={@stats.total} icon="hero-play-circle" />
          <.stat_mini
            label="Completed"
            value={@stats.completed}
            icon="hero-check-circle"
            color="text-green-500"
          />
          <.stat_mini
            label="Failed"
            value={@stats.failed}
            icon="hero-x-circle"
            color="text-red-500"
          />
          <.stat_mini label="Avg Duration" value={@stats.avg_duration} icon="hero-clock" />
        </div>
      <% end %>

      <%= if @executions == [] do %>
        <.empty_state
          icon="hero-clock"
          title="No executions yet"
          description="Trigger this flow via its webhook to see execution history here."
        />
      <% else %>
        <.card>
          <.card_content class="p-0">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b bg-muted/30">
                  <th class="px-4 py-2.5 text-left text-xs font-medium text-muted-foreground uppercase tracking-wider">
                    <span class="flex items-center gap-1.5">
                      <.icon name="hero-signal-mini" class="size-3.5" /> Status
                    </span>
                  </th>
                  <th class="px-4 py-2.5 text-left text-xs font-medium text-muted-foreground uppercase tracking-wider">
                    <span class="flex items-center gap-1.5">
                      <.icon name="hero-finger-print-mini" class="size-3.5" /> Execution ID
                    </span>
                  </th>
                  <th class="px-4 py-2.5 text-left text-xs font-medium text-muted-foreground uppercase tracking-wider">
                    <span class="flex items-center gap-1.5">
                      <.icon name="hero-clock-mini" class="size-3.5" /> Duration
                    </span>
                  </th>
                  <th class="px-4 py-2.5 text-left text-xs font-medium text-muted-foreground uppercase tracking-wider">
                    <span class="flex items-center gap-1.5">
                      <.icon name="hero-calendar-mini" class="size-3.5" /> Started
                    </span>
                  </th>
                  <th class="px-4 py-2.5 text-right text-xs font-medium text-muted-foreground uppercase tracking-wider">
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={exec <- @executions}
                  class="border-b last:border-0 hover:bg-muted/20 transition-colors cursor-pointer group"
                  phx-click={JS.navigate(~p"/flows/#{@flow.id}/executions/#{exec.id}")}
                >
                  <td class="px-4 py-2.5">
                    <div class={"inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium #{status_badge(exec.status)}"}>
                      <.icon name={status_icon(exec.status)} class="size-3.5" />
                      {exec.status}
                    </div>
                  </td>
                  <td class="px-4 py-2.5">
                    <span class="text-xs font-mono text-muted-foreground">
                      {short_id(exec.id)}
                    </span>
                  </td>
                  <td class="px-4 py-2.5">
                    <span class="text-xs font-mono">{format_duration(exec.duration_ms)}</span>
                  </td>
                  <td class="px-4 py-2.5 text-xs text-muted-foreground">
                    {format_time(exec.inserted_at)}
                  </td>
                  <td class="px-4 py-2.5 text-right">
                    <.icon
                      name="hero-chevron-right-mini"
                      class="size-4 text-muted-foreground/50 group-hover:text-foreground transition-colors"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </.card_content>
        </.card>
      <% end %>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "text-muted-foreground"

  defp stat_mini(assigns) do
    ~H"""
    <div class="flex items-center gap-3 rounded-lg border bg-card px-3 py-2.5">
      <.icon name={@icon} class={"size-4 #{@color}"} />
      <div>
        <div class="text-xs text-muted-foreground">{@label}</div>
        <div class="text-sm font-semibold">{@value}</div>
      </div>
    </div>
    """
  end

  @spec compute_stats(list()) :: map()
  defp compute_stats(executions) do
    total = length(executions)
    completed = Enum.count(executions, &(&1.status == "completed"))
    failed = Enum.count(executions, &(&1.status == "failed"))

    avg =
      executions
      |> Enum.map(& &1.duration_ms)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> "—"
        durations -> format_duration(div(Enum.sum(durations), length(durations)))
      end

    %{total: total, completed: completed, failed: failed, avg_duration: avg}
  end

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

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: "—"

  defp format_duration(nil), do: "—"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end
end
