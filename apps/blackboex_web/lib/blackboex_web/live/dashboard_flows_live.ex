defmodule BlackboexWeb.DashboardFlowsLive do
  @moduledoc """
  Dashboard Flows tab. Shows flow execution metrics, success rates, and top flows.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.Charts
  import BlackboexWeb.Components.Shared.StatCard
  import BlackboexWeb.Components.Shared.StatFigure
  import BlackboexWeb.Components.Shared.DashboardHelpers
  import BlackboexWeb.Components.Shared.DashboardPageHeader
  import BlackboexWeb.Components.Shared.DashboardSection

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
      <.dashboard_page_header
        icon="hero-arrow-path"
        icon_class="text-accent-violet"
        title="Flow Metrics"
        subtitle="Execution metrics for your automation flows"
        active_tab="flows"
        period={@period}
      />

      <%!-- Stat cards --%>
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <.stat_card
          label={"Executions (#{period_label(@period)})"}
          value={format_number(@metrics.total_executions)}
          icon="hero-bolt-mini"
          icon_class="text-accent-sky"
        />
        <.stat_card
          label={"Success Rate (#{period_label(@period)})"}
          value={"#{@metrics.success_rate}%"}
          icon="hero-check-circle-mini"
          icon_class="text-accent-emerald"
        />
        <.stat_card
          label={"Failed (#{period_label(@period)})"}
          value={format_number(@metrics.failed)}
          icon="hero-x-circle-mini"
          icon_class="text-accent-red"
        />
        <.stat_card
          label={"Avg Duration (#{period_label(@period)})"}
          value={format_duration(@metrics.avg_duration_ms)}
          icon="hero-clock-mini"
          icon_class="text-accent-amber"
        />
      </div>

      <%!-- Charts --%>
      <div class="grid gap-4 lg:grid-cols-2">
        <.dashboard_section icon="hero-bolt-mini" icon_class="text-accent-sky" title="Executions">
          <.bar_chart data={@metrics.executions_series} />
        </.dashboard_section>
        <.dashboard_section icon="hero-x-circle-mini" icon_class="text-accent-red" title="Failures">
          <.bar_chart data={@metrics.failures_series} color="var(--color-chart-2)" />
        </.dashboard_section>
      </div>

      <.dashboard_section
        icon="hero-clock-mini"
        icon_class="text-accent-amber"
        title="Avg Duration (ms)"
      >
        <.line_chart data={@metrics.duration_series} color="var(--color-chart-3)" />
      </.dashboard_section>

      <%!-- Status distribution --%>
      <.dashboard_section
        icon="hero-chart-pie-mini"
        icon_class="text-accent-purple"
        title="Status Distribution"
      >
        <div class="grid grid-cols-5 gap-3 text-center">
          <.stat_figure
            value={@extended.status_distribution.pending}
            label="Pending"
            color="text-muted-foreground"
          />
          <.stat_figure
            value={@extended.status_distribution.running}
            label="Running"
            color="text-status-running-foreground"
          />
          <.stat_figure
            value={@extended.status_distribution.completed}
            label="Completed"
            color="text-status-completed-foreground"
          />
          <.stat_figure
            value={@extended.status_distribution.failed}
            label="Failed"
            color="text-status-failed-foreground"
          />
          <.stat_figure
            value={@extended.status_distribution.halted}
            label="Halted"
            color="text-status-halted-foreground"
          />
        </div>
      </.dashboard_section>

      <%!-- Top Flows table --%>
      <.dashboard_section
        icon="hero-arrow-trending-up-mini"
        icon_class="text-accent-violet"
        title="Top Flows by Executions"
      >
        <.table id="top-flows" rows={Enum.with_index(@metrics.top_flows, 1)}>
          <:col :let={{_flow, idx}} label="#">{idx}</:col>
          <:col :let={{flow, _idx}} label="Name">{flow.name}</:col>
          <:col :let={{flow, _idx}} label="Executions">{format_number(flow.executions)}</:col>
          <:col :let={{flow, _idx}} label="Avg Duration">{format_duration(flow.avg_duration)}</:col>
          <:col :let={{flow, _idx}} label="Success Rate">{"#{flow.success_rate}%"}</:col>
        </.table>
      </.dashboard_section>

      <%!-- Slowest Executions --%>
      <.dashboard_section
        :if={@extended.longest_executions != []}
        icon="hero-clock-mini"
        icon_class="text-accent-orange"
        title="Slowest Executions"
      >
        <.table id="slowest-execs" rows={@extended.longest_executions}>
          <:col :let={row} label="Flow">{row.flow_name}</:col>
          <:col :let={row} label="Status">
            <span class={execution_status_text_class(row.status)}>{row.status}</span>
          </:col>
          <:col :let={row} label="Duration">{format_duration(row.duration_ms)}</:col>
        </.table>
      </.dashboard_section>

      <%!-- Recent Failures --%>
      <.dashboard_section
        :if={@extended.recent_failures != []}
        icon="hero-x-circle-mini"
        icon_class="text-accent-red"
        title="Recent Failures"
      >
        <.table id="recent-failures" rows={@extended.recent_failures}>
          <:col :let={row} label="Flow">{row.flow_name}</:col>
          <:col :let={row} label="Error">
            <span class="text-xs font-mono truncate max-w-xs block">{truncate(row.error, 80)}</span>
          </:col>
        </.table>
      </.dashboard_section>
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

  @spec truncate(String.t() | nil, non_neg_integer()) :: String.t()
  defp truncate(nil, _), do: "-"
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max) <> "..."
end
