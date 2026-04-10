defmodule BlackboexWeb.DashboardApisLive do
  @moduledoc """
  Dashboard APIs tab. Shows API call metrics, error rates, latency charts, and top APIs.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.Charts
  import BlackboexWeb.Components.Shared.StatCard
  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Card

  alias Blackboex.Apis.DashboardQueries

  @valid_periods ~w(24h 7d 30d)

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    period = "24h"

    socket =
      if org do
        load_api_metrics(socket, org, period)
      else
        assign(socket,
          metrics: empty_metrics(),
          extended: empty_extended(),
          period: period,
          page_title: "Dashboard - APIs"
        )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) when period in @valid_periods do
    org = socket.assigns.current_scope.organization

    if org do
      metrics = DashboardQueries.get_dashboard_metrics(org.id, period)
      extended = DashboardQueries.get_api_extended_metrics(org.id, period)
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
          <.icon name="hero-cube" class="size-5 text-blue-400" /> API Metrics
        </span>
        <:subtitle>Performance and usage metrics for your APIs</:subtitle>
        <:actions>
          <div class="flex items-center gap-3">
            <.dashboard_nav active="apis" />
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
          label={"Calls (#{period_label(@period)})"}
          value={format_number(total_calls(@metrics))}
          icon="hero-signal-mini"
          icon_class="text-sky-400"
        />
        <.stat_card
          label={"Errors (#{period_label(@period)})"}
          value={format_number(total_errors(@metrics))}
          icon="hero-exclamation-circle-mini"
          icon_class="text-red-400"
        />
        <.stat_card
          label={"Avg Latency (#{period_label(@period)})"}
          value={format_latency(avg_latency(@metrics))}
          icon="hero-clock-mini"
          icon_class="text-amber-400"
        />
        <.stat_card
          label={"Error Rate (#{period_label(@period)})"}
          value={error_rate(@metrics)}
          icon="hero-exclamation-triangle-mini"
          icon_class="text-orange-400"
        />
      </div>

      <%!-- Charts --%>
      <div class="grid gap-4 lg:grid-cols-2">
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-signal-mini" class="size-3.5 text-sky-400" /> API Calls
            </p>
            <.bar_chart data={@metrics.calls_series} />
          </.card_content>
        </.card>
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-exclamation-circle-mini" class="size-3.5 text-red-400" /> Errors
            </p>
            <.bar_chart data={@metrics.errors_series} color="var(--color-chart-2)" />
          </.card_content>
        </.card>
      </div>

      <div class="grid gap-4 lg:grid-cols-2">
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-clock-mini" class="size-3.5 text-amber-400" /> Avg Latency (ms)
            </p>
            <.line_chart data={@metrics.latency_avg_series} />
          </.card_content>
        </.card>
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-clock-mini" class="size-3.5 text-violet-400" /> P95 Latency (ms)
            </p>
            <.line_chart data={@metrics.latency_p95_series} color="var(--color-chart-4)" />
          </.card_content>
        </.card>
      </div>

      <%!-- Extended metrics row --%>
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <.stat_card
          label={"Unique Consumers (#{period_label(@period)})"}
          value={format_number(@extended.unique_consumers)}
          icon="hero-user-group-mini"
          icon_class="text-indigo-400"
        />
        <.stat_card
          label="2xx Responses"
          value={format_number(@extended.status_distribution.s2xx)}
          icon="hero-check-circle-mini"
          icon_class="text-emerald-400"
        />
        <.stat_card
          label="4xx / 5xx Errors"
          value={"#{format_number(@extended.status_distribution.s4xx)} / #{format_number(@extended.status_distribution.s5xx)}"}
          icon="hero-exclamation-triangle-mini"
          icon_class="text-red-400"
        />
        <.stat_card
          label="Avg Payload Size"
          value={"#{format_bytes(@extended.avg_request_size)} / #{format_bytes(@extended.avg_response_size)}"}
          icon="hero-arrows-right-left-mini"
          icon_class="text-cyan-400"
        />
      </div>

      <%!-- Top APIs table --%>
      <.card>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-arrow-trending-up-mini" class="size-3.5 text-sky-400" />
            Top APIs by Calls
          </p>
          <.table id="top-apis" rows={Enum.with_index(@metrics.top_apis, 1)}>
            <:col :let={{_api, idx}} label="#">{idx}</:col>
            <:col :let={{api, _idx}} label="Name">{api.name}</:col>
            <:col :let={{api, _idx}} label="Calls">{format_number(api.calls)}</:col>
            <:col :let={{api, _idx}} label="Avg Latency">{format_latency(api.avg_latency)}</:col>
          </.table>
        </.card_content>
      </.card>

      <%!-- API Key usage table --%>
      <.card :if={@extended.api_key_usage != []}>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-key-mini" class="size-3.5 text-amber-400" /> Usage by API Key
          </p>
          <.table id="api-key-usage" rows={@extended.api_key_usage}>
            <:col :let={row} label="Key">
              <span class="font-mono text-xs">{row.key_prefix}...</span>
              <span class="ml-1 text-muted-foreground">{row.key_label}</span>
            </:col>
            <:col :let={row} label="Calls">{format_number(row.calls)}</:col>
            <:col :let={row} label="Errors">{format_number(row.errors)}</:col>
            <:col :let={row} label="Avg Latency">{format_latency(row.avg_latency)}</:col>
          </.table>
        </.card_content>
      </.card>
    </div>
    """
  end

  # -- Data loading --

  defp load_api_metrics(socket, org, period) do
    metrics = DashboardQueries.get_dashboard_metrics(org.id, period)
    extended = DashboardQueries.get_api_extended_metrics(org.id, period)

    assign(socket,
      metrics: metrics,
      extended: extended,
      period: period,
      page_title: "Dashboard - APIs"
    )
  end

  defp empty_metrics do
    %{
      calls_series: [],
      errors_series: [],
      latency_avg_series: [],
      latency_p95_series: [],
      top_apis: []
    }
  end

  defp empty_extended do
    %{
      unique_consumers: 0,
      status_distribution: %{s2xx: 0, s3xx: 0, s4xx: 0, s5xx: 0},
      avg_request_size: nil,
      avg_response_size: nil,
      api_key_usage: []
    }
  end

  # -- Template helpers --

  defp period_label("24h"), do: "today"
  defp period_label("7d"), do: "7d"
  defp period_label("30d"), do: "30d"
  defp period_label(_), do: ""

  defp total_calls(%{calls_series: s}), do: s |> Enum.map(& &1.value) |> Enum.sum()
  defp total_errors(%{errors_series: s}), do: s |> Enum.map(& &1.value) |> Enum.sum()

  defp avg_latency(%{latency_avg_series: series}) do
    values = series |> Enum.map(& &1.value) |> Enum.reject(&(&1 == 0))

    case values do
      [] -> nil
      vals -> Float.round(Enum.sum(vals) / length(vals), 1)
    end
  end

  defp error_rate(metrics) do
    calls = total_calls(metrics)
    errors = total_errors(metrics)

    if calls > 0,
      do: "#{Float.round(errors / calls * 100, 1)}%",
      else: "0%"
  end

  @spec format_number(number() | nil) :: String.t()
  defp format_number(nil), do: "0"

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.map_join(",", &Enum.join/1)
  end

  defp format_number(n) when is_float(n), do: format_number(trunc(n))

  @spec format_latency(float() | integer() | nil) :: String.t()
  defp format_latency(nil), do: "- ms"
  defp format_latency(ms) when is_float(ms), do: "#{Float.round(ms, 1)}ms"
  defp format_latency(ms) when is_integer(ms), do: "#{ms}ms"

  @spec format_bytes(float() | integer() | nil) :: String.t()
  defp format_bytes(nil), do: "-"

  defp format_bytes(b) when is_number(b) and b >= 1_048_576,
    do: "#{Float.round(b / 1_048_576, 1)} MB"

  defp format_bytes(b) when is_number(b) and b >= 1024, do: "#{Float.round(b / 1024, 1)} KB"
  defp format_bytes(b) when is_number(b), do: "#{trunc(b)} B"
end
