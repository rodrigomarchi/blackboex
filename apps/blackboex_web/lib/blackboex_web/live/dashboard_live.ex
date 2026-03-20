defmodule BlackboexWeb.DashboardLive do
  @moduledoc """
  Main dashboard LiveView. Shows org summary, API stats, usage, and recent activity
  with time-series charts and period selection.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Charts

  alias Blackboex.Apis.DashboardQueries
  alias Blackboex.Audit
  alias Blackboex.Billing.Enforcement

  @valid_periods ~w(24h 7d 30d)

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    period = "24h"

    socket =
      if org do
        load_dashboard(socket, org, period)
      else
        assign(socket,
          summary: %{total_apis: 0, calls_today: 0, errors_today: 0, avg_latency_today: nil},
          metrics: empty_metrics(),
          usage: nil,
          llm_usage: empty_llm_usage(),
          recent_activity: [],
          period: period,
          page_title: "Dashboard"
        )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) when period in @valid_periods do
    org = socket.assigns.current_scope.organization

    if org do
      metrics = DashboardQueries.get_dashboard_metrics(org.id, period)
      llm_usage = DashboardQueries.get_llm_usage_series(org.id, period)

      {:noreply, assign(socket, metrics: metrics, llm_usage: llm_usage, period: period)}
    else
      {:noreply, assign(socket, period: period)}
    end
  end

  def handle_event("set_period", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Dashboard</h1>
          <p class="text-muted-foreground">Overview of your workspace</p>
        </div>
        <div class="flex gap-1">
          <button
            :for={{value, label} <- [{"24h", "Today"}, {"7d", "7 days"}, {"30d", "30 days"}]}
            phx-click="set_period"
            phx-value-period={value}
            class={[
              "rounded-md px-3 py-1 text-sm font-medium",
              if(value == @period,
                do: "bg-primary text-primary-foreground",
                else: "border text-muted-foreground hover:bg-accent"
              )
            ]}
          >
            {label}
          </button>
        </div>
      </div>

      <%= if @summary.total_apis == 0 do %>
        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
          <div class="flex flex-col items-center justify-center space-y-4 py-12">
            <.logo_icon class="size-12 text-muted-foreground" />
            <div class="text-center space-y-2">
              <h3 class="text-xl font-semibold">Welcome to BlackBoex</h3>
              <p class="text-sm text-muted-foreground max-w-md">
                Transform natural language into production-ready Elixir APIs.
                Create your first API to get started.
              </p>
            </div>
            <.link
              navigate={~p"/apis/new"}
              class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
            >
              Create your first API
            </.link>
          </div>
        </div>
      <% else %>
        <%!-- Row 1: Stat cards --%>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm text-muted-foreground">Total APIs</p>
            <p class="text-2xl font-bold">{format_number(@summary.total_apis)}</p>
          </div>
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm text-muted-foreground">Calls ({period_label(@period)})</p>
            <p class="text-2xl font-bold">{format_number(period_total_calls(@metrics))}</p>
          </div>
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm text-muted-foreground">Errors ({period_label(@period)})</p>
            <p class="text-2xl font-bold">{format_number(period_total_errors(@metrics))}</p>
          </div>
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm text-muted-foreground">Avg Latency ({period_label(@period)})</p>
            <p class="text-2xl font-bold">{format_latency(period_avg_latency(@metrics))}</p>
          </div>
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm text-muted-foreground">LLM Gens</p>
            <p class="text-2xl font-bold">
              {format_number(period_total_gens(@llm_usage))}
            </p>
          </div>
        </div>

        <%!-- Row 2: API Calls + Errors charts --%>
        <div class="grid gap-4 lg:grid-cols-2">
          <div class="rounded-lg border bg-card p-4">
            <.bar_chart data={@metrics.calls_series} title="API Calls" />
          </div>
          <div class="rounded-lg border bg-card p-4">
            <.bar_chart data={@metrics.errors_series} title="Errors" color="#ef4444" />
          </div>
        </div>

        <%!-- Row 3: Latency chart + LLM Usage --%>
        <div class="grid gap-4 lg:grid-cols-2">
          <div class="rounded-lg border bg-card p-4">
            <.line_chart data={@metrics.latency_avg_series} title="Avg Latency (ms)" />
          </div>
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm font-medium text-zinc-700 mb-4">LLM Usage</p>
            <div class="space-y-3">
              <div>
                <div class="flex justify-between text-sm mb-1">
                  <span>Generations</span>
                  <span>{format_number(llm_gens_used(@usage))} / {format_llm_limit(@usage)}</span>
                </div>
                <div class="h-2 rounded-full bg-muted">
                  <div
                    class="h-full rounded-full bg-primary"
                    style={"width: #{min(llm_gens_pct(@usage), 100)}%"}
                  >
                  </div>
                </div>
              </div>
              <div class="flex justify-between text-sm py-2 border-t">
                <span class="text-muted-foreground">Tokens In</span>
                <span class="font-medium">{format_tokens(@llm_usage.tokens_in_total)}</span>
              </div>
              <div class="flex justify-between text-sm py-2 border-t">
                <span class="text-muted-foreground">Tokens Out</span>
                <span class="font-medium">{format_tokens(@llm_usage.tokens_out_total)}</span>
              </div>
              <div class="flex justify-between text-sm py-2 border-t">
                <span class="text-muted-foreground">LLM Cost</span>
                <span class="font-medium">
                  ${Float.round(@llm_usage.cost_total_cents / 100, 2)}
                </span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Row 4: Top APIs + Recent Activity --%>
        <div class="grid gap-4 lg:grid-cols-2">
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm font-medium text-zinc-700 mb-3">Top APIs by Calls</p>
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b text-left text-muted-foreground">
                  <th class="pb-2 font-medium">#</th>
                  <th class="pb-2 font-medium">Name</th>
                  <th class="pb-2 font-medium text-right">Calls</th>
                  <th class="pb-2 font-medium text-right">Avg Latency</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{api, idx} <- Enum.with_index(@metrics.top_apis, 1)}
                  class="border-b last:border-0"
                >
                  <td class="py-2 text-muted-foreground">{idx}</td>
                  <td class="py-2 font-medium">{api.name}</td>
                  <td class="py-2 text-right">{format_number(api.calls)}</td>
                  <td class="py-2 text-right">{format_latency(api.avg_latency)}</td>
                </tr>
                <tr :if={@metrics.top_apis == []}>
                  <td colspan="4" class="py-4 text-center text-muted-foreground">
                    No API calls in this period
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm font-medium text-zinc-700 mb-3">Recent Activity</p>
            <div :if={@recent_activity == []} class="py-4 text-center text-sm text-muted-foreground">
              No recent activity
            </div>
            <div :if={@recent_activity != []} class="divide-y">
              <div
                :for={activity <- @recent_activity}
                class="flex items-center justify-between py-2"
              >
                <span class="text-sm">{format_action(activity.action)}</span>
                <span class="text-xs text-muted-foreground">{relative_time(activity.timestamp)}</span>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # -- Data loading --

  defp load_dashboard(socket, org, period) do
    summary = DashboardQueries.get_org_summary(org.id)
    metrics = DashboardQueries.get_dashboard_metrics(org.id, period)
    usage = Enforcement.get_usage_details(org)
    llm_usage = DashboardQueries.get_llm_usage_series(org.id, period)
    recent_activity = Audit.list_recent_activity(org.id, 5)

    assign(socket,
      summary: summary,
      metrics: metrics,
      usage: usage,
      llm_usage: llm_usage,
      recent_activity: recent_activity,
      period: period,
      page_title: "Dashboard"
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

  defp empty_llm_usage do
    %{
      generations_series: [],
      tokens_in_total: 0,
      tokens_out_total: 0,
      cost_total_cents: 0
    }
  end

  # -- Template helpers --

  defp period_label("24h"), do: "today"
  defp period_label("7d"), do: "7d"
  defp period_label("30d"), do: "30d"
  defp period_label(_), do: ""

  @spec period_total_calls(map()) :: non_neg_integer()
  defp period_total_calls(%{calls_series: series}) do
    series |> Enum.map(& &1.value) |> Enum.sum()
  end

  @spec period_total_errors(map()) :: non_neg_integer()
  defp period_total_errors(%{errors_series: series}) do
    series |> Enum.map(& &1.value) |> Enum.sum()
  end

  @spec period_total_gens(map()) :: non_neg_integer()
  defp period_total_gens(%{generations_series: series}) do
    series |> Enum.map(& &1.value) |> Enum.sum()
  end

  @spec period_avg_latency(map()) :: float() | nil
  defp period_avg_latency(%{latency_avg_series: series}) do
    values = series |> Enum.map(& &1.value) |> Enum.reject(&(&1 == 0))

    case values do
      [] -> nil
      vals -> Float.round(Enum.sum(vals) / length(vals), 1)
    end
  end

  @spec llm_gens_used(map() | nil) :: non_neg_integer()
  defp llm_gens_used(nil), do: 0
  defp llm_gens_used(%{llm_generations_month: %{used: used}}), do: used

  @spec llm_gens_pct(map() | nil) :: float()
  defp llm_gens_pct(nil), do: 0.0
  defp llm_gens_pct(%{llm_generations_month: %{pct: pct}}), do: pct

  @spec format_llm_limit(map() | nil) :: String.t()
  defp format_llm_limit(nil), do: "-"

  defp format_llm_limit(%{llm_generations_month: %{limit: :unlimited}}),
    do: "unlimited"

  defp format_llm_limit(%{llm_generations_month: %{limit: limit}}),
    do: format_number(limit)

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

  @spec format_action(String.t()) :: String.t()
  defp format_action(action) when is_binary(action) do
    action
    |> String.split(".")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_action(_), do: "Unknown action"

  @spec relative_time(DateTime.t() | NaiveDateTime.t() | nil) :: String.t()
  defp relative_time(nil), do: ""

  defp relative_time(%NaiveDateTime{} = naive) do
    naive
    |> DateTime.from_naive!("Etc/UTC")
    |> relative_time()
  end

  defp relative_time(%DateTime{} = dt) do
    diff = max(DateTime.diff(DateTime.utc_now(), dt, :second), 0)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(dt, "%b %d")
    end
  end

  @spec format_tokens(non_neg_integer() | nil) :: String.t()
  defp format_tokens(nil), do: "0"
  defp format_tokens(0), do: "0"

  defp format_tokens(n) when n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_tokens(n) when n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_tokens(n), do: Integer.to_string(n)
end
