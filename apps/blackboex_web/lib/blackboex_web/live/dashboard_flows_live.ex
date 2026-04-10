defmodule BlackboexWeb.DashboardFlowsLive do
  @moduledoc """
  Dashboard Flows tab. Shows flow execution metrics, success rates, and top flows.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.Charts
  import BlackboexWeb.Components.Shared.StatCard
  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.DashboardHelpers
  import BlackboexWeb.Components.Card

  alias Blackboex.Apis.DashboardQueries

  @valid_periods ~w(24h 7d 30d)

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    period = "24h"

    socket =
      if org do
        load_flow_metrics(socket, org, period)
      else
        assign(socket,
          metrics: empty_metrics(),
          extended: empty_extended(),
          period: period,
          page_title: "Dashboard - Flows"
        )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) when period in @valid_periods do
    org = socket.assigns.current_scope.organization

    if org do
      metrics = DashboardQueries.get_flow_metrics(org.id, period)
      extended = DashboardQueries.get_flow_extended_metrics(org.id, period)
      {:noreply, assign(socket, metrics: metrics, extended: extended, period: period)}
    else
      {:noreply, assign(socket, period: period)}
    end
  end

  def handle_event("set_period", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-arrow-path" class="size-5 text-violet-400" /> Flow Metrics
        </span>
        <:subtitle>Execution metrics for your automation flows</:subtitle>
        <:actions>
          <div class="flex items-center gap-3">
            <.dashboard_nav active="flows" />
            <div class="flex gap-1">
              <.button
                :for={{value, label} <- [{"24h", "Today"}, {"7d", "7 days"}, {"30d", "30 days"}]}
                phx-click="set_period"
                phx-value-period={value}
                variant={if value == @period, do: "primary", else: "default"}
                size="sm"
              >
                {label}
              </.button>
            </div>
          </div>
        </:actions>
      </.header>

      <%!-- Stat cards --%>
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <.stat_card
          label={"Executions (#{period_label(@period)})"}
          value={format_number(@metrics.total_executions)}
          icon="hero-bolt-mini"
          icon_class="text-sky-400"
        />
        <.stat_card
          label={"Success Rate (#{period_label(@period)})"}
          value={"#{@metrics.success_rate}%"}
          icon="hero-check-circle-mini"
          icon_class="text-emerald-400"
        />
        <.stat_card
          label={"Failed (#{period_label(@period)})"}
          value={format_number(@metrics.failed)}
          icon="hero-x-circle-mini"
          icon_class="text-red-400"
        />
        <.stat_card
          label={"Avg Duration (#{period_label(@period)})"}
          value={format_duration(@metrics.avg_duration_ms)}
          icon="hero-clock-mini"
          icon_class="text-amber-400"
        />
      </div>

      <%!-- Charts --%>
      <div class="grid gap-4 lg:grid-cols-2">
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-bolt-mini" class="size-3.5 text-sky-400" /> Executions
            </p>
            <.bar_chart data={@metrics.executions_series} />
          </.card_content>
        </.card>
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-x-circle-mini" class="size-3.5 text-red-400" /> Failures
            </p>
            <.bar_chart data={@metrics.failures_series} color="var(--color-chart-2)" />
          </.card_content>
        </.card>
      </div>

      <.card>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-clock-mini" class="size-3.5 text-amber-400" /> Avg Duration (ms)
          </p>
          <.line_chart data={@metrics.duration_series} color="var(--color-chart-3)" />
        </.card_content>
      </.card>

      <%!-- Status distribution --%>
      <.card>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-chart-pie-mini" class="size-3.5 text-indigo-400" /> Status Distribution
          </p>
          <div class="grid grid-cols-5 gap-3 text-center">
            <div>
              <p class="text-2xl font-bold text-muted-foreground">
                {@extended.status_distribution.pending}
              </p>
              <p class="text-xs text-muted-foreground">Pending</p>
            </div>
            <div>
              <p class="text-2xl font-bold text-sky-400">{@extended.status_distribution.running}</p>
              <p class="text-xs text-muted-foreground">Running</p>
            </div>
            <div>
              <p class="text-2xl font-bold text-emerald-400">
                {@extended.status_distribution.completed}
              </p>
              <p class="text-xs text-muted-foreground">Completed</p>
            </div>
            <div>
              <p class="text-2xl font-bold text-red-400">{@extended.status_distribution.failed}</p>
              <p class="text-xs text-muted-foreground">Failed</p>
            </div>
            <div>
              <p class="text-2xl font-bold text-amber-400">{@extended.status_distribution.halted}</p>
              <p class="text-xs text-muted-foreground">Halted</p>
            </div>
          </div>
        </.card_content>
      </.card>

      <%!-- Top Flows table --%>
      <.card>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-arrow-trending-up-mini" class="size-3.5 text-violet-400" />
            Top Flows by Executions
          </p>
          <.table id="top-flows" rows={Enum.with_index(@metrics.top_flows, 1)}>
            <:col :let={{_flow, idx}} label="#">{idx}</:col>
            <:col :let={{flow, _idx}} label="Name">{flow.name}</:col>
            <:col :let={{flow, _idx}} label="Executions">{format_number(flow.executions)}</:col>
            <:col :let={{flow, _idx}} label="Avg Duration">{format_duration(flow.avg_duration)}</:col>
            <:col :let={{flow, _idx}} label="Success Rate">{"#{flow.success_rate}%"}</:col>
          </.table>
        </.card_content>
      </.card>

      <%!-- Slowest Executions --%>
      <.card :if={@extended.longest_executions != []}>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-clock-mini" class="size-3.5 text-orange-400" /> Slowest Executions
          </p>
          <.table id="slowest-execs" rows={@extended.longest_executions}>
            <:col :let={row} label="Flow">{row.flow_name}</:col>
            <:col :let={row} label="Status">
              <span class={status_color(row.status)}>{row.status}</span>
            </:col>
            <:col :let={row} label="Duration">{format_duration(row.duration_ms)}</:col>
          </.table>
        </.card_content>
      </.card>

      <%!-- Recent Failures --%>
      <.card :if={@extended.recent_failures != []}>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-x-circle-mini" class="size-3.5 text-red-400" /> Recent Failures
          </p>
          <.table id="recent-failures" rows={@extended.recent_failures}>
            <:col :let={row} label="Flow">{row.flow_name}</:col>
            <:col :let={row} label="Error">
              <span class="text-xs font-mono truncate max-w-xs block">{truncate(row.error, 80)}</span>
            </:col>
          </.table>
        </.card_content>
      </.card>
    </div>
    """
  end

  # -- Data loading --

  defp load_flow_metrics(socket, org, period) do
    metrics = DashboardQueries.get_flow_metrics(org.id, period)
    extended = DashboardQueries.get_flow_extended_metrics(org.id, period)

    assign(socket,
      metrics: metrics,
      extended: extended,
      period: period,
      page_title: "Dashboard - Flows"
    )
  end

  defp empty_metrics do
    %{
      total_executions: 0,
      completed: 0,
      failed: 0,
      avg_duration_ms: nil,
      success_rate: 0.0,
      executions_series: [],
      failures_series: [],
      duration_series: [],
      top_flows: []
    }
  end

  defp empty_extended do
    %{
      status_distribution: %{pending: 0, running: 0, completed: 0, failed: 0, halted: 0},
      longest_executions: [],
      recent_failures: []
    }
  end

  # -- Template helpers --

  @spec status_color(String.t()) :: String.t()
  defp status_color("completed"), do: "text-emerald-400"
  defp status_color("failed"), do: "text-red-400"
  defp status_color("running"), do: "text-sky-400"
  defp status_color("halted"), do: "text-amber-400"
  defp status_color(_), do: "text-muted-foreground"

  @spec truncate(String.t() | nil, non_neg_integer()) :: String.t()
  defp truncate(nil, _), do: "-"
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max) <> "..."
end
