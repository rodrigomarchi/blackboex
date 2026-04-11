defmodule BlackboexWeb.DashboardLlmLive do
  @moduledoc """
  Dashboard LLM tab. Shows LLM usage by model/provider, cost breakdown,
  conversation stats, and agent run metrics.
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
    period = "30d"

    socket =
      if org do
        load_llm_metrics(socket, org, period)
      else
        assign(socket, metrics: empty_metrics(), period: period, page_title: "Dashboard - LLM")
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) when period in @valid_periods do
    org = socket.assigns.current_scope.organization

    if org do
      metrics = DashboardQueries.get_llm_metrics(org.id, period)
      {:noreply, assign(socket, metrics: metrics, period: period)}
    else
      {:noreply, assign(socket, period: period)}
    end
  end

  def handle_event("set_period", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.dashboard_page_header
        icon="hero-sparkles"
        icon_class="text-accent-violet"
        title="LLM Metrics"
        subtitle="AI model usage, costs, and performance"
        active_tab="llm"
        period={@period}
      />

      <%!-- Stat cards --%>
      <.stat_grid cols="5">
        <.stat_card
          label={"LLM Calls (#{period_label(@period)})"}
          value={format_number(@metrics.total_calls)}
          icon="hero-sparkles-mini"
          icon_class="text-accent-violet"
        />
        <.stat_card
          label={"Total Cost (#{period_label(@period)})"}
          value={format_cost(@metrics.total_cost_cents)}
          icon="hero-currency-dollar-mini"
          icon_class="text-accent-amber"
        />
        <.stat_card
          label={"Tokens In (#{period_label(@period)})"}
          value={format_tokens(@metrics.total_input_tokens)}
          icon="hero-arrow-down-tray-mini"
          icon_class="text-accent-blue"
        />
        <.stat_card
          label={"Tokens Out (#{period_label(@period)})"}
          value={format_tokens(@metrics.total_output_tokens)}
          icon="hero-arrow-up-tray-mini"
          icon_class="text-accent-emerald"
        />
        <.stat_card
          label={"Avg Duration (#{period_label(@period)})"}
          value={format_duration(@metrics.avg_duration_ms)}
          icon="hero-clock-mini"
          icon_class="text-accent-sky"
        />
      </.stat_grid>

      <%!-- Charts --%>
      <.chart_grid>
        <.dashboard_section
          icon="hero-sparkles-mini"
          icon_class="text-accent-violet"
          title="LLM Calls"
        >
          <.bar_chart data={@metrics.calls_series} color="var(--color-chart-4)" />
        </.dashboard_section>
        <.dashboard_section
          icon="hero-currency-dollar-mini"
          icon_class="text-accent-amber"
          title="Cost (cents)"
        >
          <.line_chart data={@metrics.cost_series} color="var(--color-chart-5)" />
        </.dashboard_section>
      </.chart_grid>

      <.chart_grid>
        <.dashboard_section
          icon="hero-arrow-down-tray-mini"
          icon_class="text-accent-blue"
          title="Tokens"
        >
          <.bar_chart data={@metrics.tokens_series} />
        </.dashboard_section>
        <.dashboard_section
          icon="hero-clock-mini"
          icon_class="text-accent-sky"
          title="Avg Duration (ms)"
        >
          <.line_chart data={@metrics.duration_series} color="var(--color-chart-3)" />
        </.dashboard_section>
      </.chart_grid>

      <%!-- Usage by Model table --%>
      <.dashboard_section
        :if={@metrics.by_model != []}
        icon="hero-cpu-chip-mini"
        icon_class="text-accent-violet"
        title="Usage by Model"
      >
        <.table id="by-model" rows={@metrics.by_model}>
          <:col :let={row} label="Provider">{row.provider}</:col>
          <:col :let={row} label="Model">{row.model}</:col>
          <:col :let={row} label="Calls">{format_number(row.calls)}</:col>
          <:col :let={row} label="Tokens In">{format_tokens(row.input_tokens)}</:col>
          <:col :let={row} label="Tokens Out">{format_tokens(row.output_tokens)}</:col>
          <:col :let={row} label="Cost">{format_cost(row.cost_cents)}</:col>
          <:col :let={row} label="Avg Duration">{format_duration(row.avg_duration_ms)}</:col>
        </.table>
      </.dashboard_section>

      <%!-- Usage by Operation --%>
      <.dashboard_section
        :if={@metrics.by_operation != []}
        icon="hero-cog-6-tooth-mini"
        icon_class="text-accent-sky"
        title="Usage by Operation"
      >
        <.table id="by-operation" rows={@metrics.by_operation}>
          <:col :let={row} label="Operation">{format_operation(row.operation)}</:col>
          <:col :let={row} label="Calls">{format_number(row.calls)}</:col>
          <:col :let={row} label="Cost">{format_cost(row.cost_cents)}</:col>
          <:col :let={row} label="Avg Duration">{format_duration(row.avg_duration_ms)}</:col>
        </.table>
      </.dashboard_section>

      <%!-- Cost by API --%>
      <.dashboard_section
        :if={@metrics.cost_by_api != []}
        icon="hero-cube-mini"
        icon_class="text-accent-blue"
        title="Cost by API"
      >
        <.table id="cost-by-api" rows={@metrics.cost_by_api}>
          <:col :let={row} label="API">{row.api_name}</:col>
          <:col :let={row} label="Calls">{format_number(row.calls)}</:col>
          <:col :let={row} label="Tokens In">{format_tokens(row.input_tokens)}</:col>
          <:col :let={row} label="Tokens Out">{format_tokens(row.output_tokens)}</:col>
          <:col :let={row} label="Cost">{format_cost(row.cost_cents)}</:col>
        </.table>
      </.dashboard_section>

      <%!-- Conversations & Runs summary --%>
      <.chart_grid>
        <.dashboard_section
          icon="hero-chat-bubble-left-right-mini"
          icon_class="text-accent-purple"
          title="Conversations"
        >
          <div class="grid grid-cols-2 gap-4">
            <.stat_figure value={format_number(@metrics.conversations.total)} label="Total" />
            <.stat_figure
              value={format_number(@metrics.conversations.active)}
              label="Active"
              color="text-status-completed-foreground"
            />
            <.stat_figure
              value={format_tokens(@metrics.conversations.total_tokens)}
              label="Total Tokens"
            />
            <.stat_figure
              value={format_cost(@metrics.conversations.total_cost_cents)}
              label="Total Cost"
            />
          </div>
        </.dashboard_section>
        <.dashboard_section
          icon="hero-play-mini"
          icon_class="text-accent-sky"
          title={"Agent Runs (#{period_label(@period)})"}
        >
          <div class="grid grid-cols-2 gap-4">
            <.stat_figure value={format_number(@metrics.runs.total)} label="Total" />
            <.stat_figure
              value={format_number(@metrics.runs.completed)}
              label="Completed"
              color="text-status-completed-foreground"
            />
            <.stat_figure
              value={format_number(@metrics.runs.failed)}
              label="Failed"
              color="text-status-failed-foreground"
            />
            <.stat_figure
              value={format_duration(@metrics.runs.avg_duration_ms)}
              label="Avg Duration"
            />
          </div>
        </.dashboard_section>
      </.chart_grid>
    </.page>
    """
  end

  # -- Data loading --

  defp load_llm_metrics(socket, org, period) do
    metrics = DashboardQueries.get_llm_metrics(org.id, period)

    assign(socket,
      metrics: metrics,
      period: period,
      page_title: "Dashboard - LLM"
    )
  end

  defp empty_metrics do
    %{
      total_calls: 0,
      total_input_tokens: 0,
      total_output_tokens: 0,
      total_cost_cents: 0,
      avg_duration_ms: nil,
      by_model: [],
      by_operation: [],
      cost_by_api: [],
      conversations: %{total: 0, active: 0, total_tokens: 0, total_cost_cents: 0},
      runs: %{total: 0, completed: 0, failed: 0, avg_iterations: nil, avg_duration_ms: nil},
      calls_series: [],
      cost_series: [],
      tokens_series: [],
      duration_series: []
    }
  end

  # -- Template helpers --

  @spec format_operation(String.t() | nil) :: String.t()
  defp format_operation(nil), do: "-"

  defp format_operation(op) when is_binary(op) do
    op
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
