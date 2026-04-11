defmodule BlackboexWeb.ApiLive.Edit.MetricsLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  require Logger

  import Ecto.Query
  import BlackboexWeb.ApiLive.Edit.EditorShell
  import BlackboexWeb.Components.UI.SectionHeading
  import BlackboexWeb.Components.Shared.StatMini

  alias Blackboex.Apis.Analytics
  alias Blackboex.Apis.MetricRollup
  alias BlackboexWeb.ApiLive.Edit.Shared

  @metric_periods %{"24h" => 1, "7d" => 7, "30d" => 30}

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  # ── Mount ─────────────────────────────────────────────────────────────

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} -> {:ok, socket |> init_assigns() |> load_metrics_data()}
      {:error, socket} -> {:ok, socket}
    end
  end

  # ── Render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="metrics">
      <div class="p-6 overflow-y-auto h-full space-y-6">
        <div class="flex items-center justify-between">
          <.section_heading level="h2" compact>Metrics</.section_heading>
          <div class="flex gap-1">
            <.button
              :for={period <- ["24h", "7d", "30d"]}
              phx-click="change_metrics_period"
              phx-value-period={period}
              variant={if @metrics_period == period, do: "primary", else: "ghost"}
              size="sm"
              class={[
                "px-3 py-1 rounded-md text-xs font-medium",
                @metrics_period != period && "bg-muted text-muted-foreground hover:bg-accent"
              ]}
            >
              {period}
            </.button>
          </div>
        </div>

        <%!-- Stat Cards --%>
        <div class="grid grid-cols-4 gap-4">
          <.stat_mini
            value={@total_invocations}
            label="Invocations"
            icon="hero-signal-mini"
            icon_class="text-accent-sky"
            size="lg"
            label_position="above"
          />
          <.stat_mini
            value={@total_errors}
            label="Errors"
            icon="hero-exclamation-circle-mini"
            icon_class="text-accent-red"
            size="lg"
            label_position="above"
          />
          <.stat_mini
            value={"#{@error_rate}%"}
            label="Error Rate"
            icon="hero-chart-bar-mini"
            icon_class="text-accent-amber"
            size="lg"
            label_position="above"
          />
          <.stat_mini
            value={"#{@avg_latency}ms"}
            label="Avg Latency"
            icon="hero-clock-mini"
            icon_class="text-accent-amber"
            size="lg"
            label_position="above"
          />
        </div>

        <%= if @invocation_data == [] do %>
          <div class="rounded-lg border border-dashed p-8 text-center">
            <.icon name="hero-chart-bar" class="size-10 mx-auto text-accent-sky mb-3" />
            <p class="text-sm font-medium">No metrics data yet</p>
            <p class="text-muted-caption mt-1">
              Publish and call your API to see stats. Data is aggregated hourly.
            </p>
          </div>
        <% else %>
          <div class="grid grid-cols-2 gap-4">
            <div class="rounded-lg border p-4">
              <BlackboexWeb.Components.Shared.Charts.bar_chart
                data={@invocation_data}
                title="Invocations"
              />
            </div>
            <div class="rounded-lg border p-4">
              <BlackboexWeb.Components.Shared.Charts.line_chart
                data={@latency_data}
                title="P95 Latency (ms)"
                color="var(--color-chart-3)"
              />
            </div>
          </div>
          <div class="rounded-lg border p-4">
            <BlackboexWeb.Components.Shared.Charts.bar_chart
              data={@error_data}
              title="Errors"
              color="var(--color-chart-2)"
            />
          </div>
        <% end %>

        <%!-- Recent Errors --%>
        <%= if @recent_errors != [] do %>
          <div class="space-y-3">
            <.section_heading level="h3" heading_class="text-sm font-semibold text-foreground">
              Recent Errors
            </.section_heading>
            <div class="rounded-lg border divide-y">
              <div
                :for={error <- @recent_errors}
                class="px-4 py-3 flex items-start gap-3 text-xs"
              >
                <span class={[
                  "shrink-0 rounded px-1.5 py-0.5 font-mono font-medium",
                  if(error.status_code >= 500,
                    do: "bg-destructive/10 text-destructive",
                    else: "bg-yellow-500/10 text-yellow-600 dark:text-yellow-400"
                  )
                ]}>
                  {error.status_code}
                </span>
                <div class="min-w-0 flex-1">
                  <p class="font-mono text-muted-foreground">
                    {error.method} {error.path}
                  </p>
                  <%= if error.error_message do %>
                    <p class="mt-1 text-destructive break-words">{error.error_message}</p>
                  <% end %>
                </div>
                <span class="shrink-0 text-muted-foreground">
                  {format_time_ago(error.inserted_at)}
                </span>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </.editor_shell>
    """
  end

  # ── handle_event: command palette ────────────────────────────────────

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
  end

  # ── handle_event: metrics tab ─────────────────────────────────────────

  @impl true
  def handle_event("change_metrics_period", %{"period" => period}, socket)
      when is_map_key(@metric_periods, period) do
    {:noreply,
     socket
     |> assign(metrics_period: period, metrics_loaded: false)
     |> load_metrics_data()}
  end

  # ── Private Helpers ───────────────────────────────────────────────────

  defp init_assigns(socket) do
    assign(socket,
      metrics_period: "7d",
      metrics_loaded: false,
      invocation_data: [],
      latency_data: [],
      error_data: [],
      total_invocations: 0,
      total_errors: 0,
      error_rate: 0.0,
      avg_latency: 0,
      recent_errors: []
    )
  end

  defp load_metrics_data(socket) do
    api_id = socket.assigns.api.id
    days = Map.fetch!(@metric_periods, socket.assigns.metrics_period)
    start_date = Date.add(Date.utc_today(), -days)

    rollups =
      from(r in MetricRollup,
        where: r.api_id == ^api_id and r.date >= ^start_date,
        order_by: [asc: r.date, asc: r.hour]
      )
      |> Blackboex.Repo.all()

    daily =
      rollups
      |> Enum.group_by(& &1.date)
      |> Enum.sort_by(fn {date, _} -> date end)
      |> Enum.map(fn {date, entries} ->
        %{
          label: Calendar.strftime(date, "%m/%d"),
          invocations: Enum.sum(Enum.map(entries, & &1.invocations)),
          errors: Enum.sum(Enum.map(entries, & &1.errors)),
          p95: entries |> Enum.map(& &1.p95_duration_ms) |> Enum.max(fn -> 0.0 end),
          avg_dur: entries |> Enum.map(& &1.avg_duration_ms) |> metrics_average()
        }
      end)

    total_invocations = Enum.sum(Enum.map(daily, & &1.invocations))
    total_errors = Enum.sum(Enum.map(daily, & &1.errors))

    error_rate =
      if total_invocations > 0,
        do: Float.round(total_errors / total_invocations * 100, 1),
        else: 0.0

    period_atom =
      case socket.assigns.metrics_period do
        "24h" -> :day
        "7d" -> :week
        "30d" -> :month
      end

    avg_latency = Analytics.avg_latency(api_id, period: period_atom)
    recent_errors = Analytics.recent_errors(api_id)

    assign(socket,
      invocation_data: Enum.map(daily, &%{label: &1.label, value: &1.invocations}),
      latency_data: Enum.map(daily, &%{label: &1.label, value: round(&1.p95)}),
      error_data: Enum.map(daily, &%{label: &1.label, value: &1.errors}),
      total_invocations: total_invocations,
      total_errors: total_errors,
      error_rate: error_rate,
      avg_latency: avg_latency,
      recent_errors: recent_errors,
      metrics_loaded: true
    )
  rescue
    error ->
      Logger.error("Failed to load metrics: #{Exception.message(error)}")

      assign(socket,
        invocation_data: [],
        latency_data: [],
        error_data: [],
        total_invocations: 0,
        total_errors: 0,
        error_rate: 0.0,
        avg_latency: 0,
        recent_errors: [],
        metrics_loaded: true
      )
  end

  defp metrics_average([]), do: 0.0
  defp metrics_average(list), do: Enum.sum(list) / length(list)

  defp format_time_ago(%NaiveDateTime{} = time) do
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), time, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp shared_shell_assigns(assigns) do
    Map.take(assigns, [
      :api,
      :versions,
      :selected_version,
      :generation_status,
      :validation_report,
      :test_summary,
      :command_palette_open,
      :command_palette_query,
      :command_palette_selected
    ])
  end
end
