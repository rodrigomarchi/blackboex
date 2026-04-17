defmodule BlackboexWeb.DashboardLive.Flows do
  @moduledoc """
  Flows tab of the dashboard. Renders aggregate flow execution metrics
  (totals by status, error rate, average duration) and the top 10 flows
  by execution count, scoped to either the current organization or the
  current project depending on the URL.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.PeriodSelector
  import BlackboexWeb.Components.Shared.StatCard

  alias Blackboex.Apis.DashboardQueries
  alias BlackboexWeb.DashboardLive.Scope

  @valid_periods ~w(24h 7d 30d)
  @default_period "24h"

  @impl true
  def mount(params, _session, socket) do
    case Scope.from_socket(socket, params) do
      nil ->
        {:ok, push_navigate(socket, to: "/")}

      scope ->
        current = socket.assigns.current_scope
        org = current.organization
        project = current.project

        {:ok,
         socket
         |> assign(:scope, scope)
         |> assign(:base_path, Scope.base_path(scope, org, project))
         |> assign(:page_title, page_title(scope, org, project))}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    period = normalize_period(params["period"])
    metrics = DashboardQueries.flow_metrics(socket.assigns.scope, period)

    {:noreply,
     socket
     |> assign(:period, period)
     |> assign(:metrics, metrics)}
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) do
    period = normalize_period(period)

    {:noreply, push_patch(socket, to: socket.assigns.base_path <> "/flows?period=" <> period)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        Flows
        <:subtitle>{scope_subtitle(@scope)}</:subtitle>
        <:actions>
          <.dashboard_nav active={:flows} base_path={@base_path} />
        </:actions>
      </.header>

      <div class="flex justify-end">
        <.period_selector period={@period} />
      </div>

      <.stat_grid cols="4">
        <.stat_card
          label="Total Flows"
          value={@metrics.total_flows}
          icon="hero-arrow-path"
          icon_class="text-accent-violet"
        />
        <.stat_card
          label="Executions"
          value={@metrics.executions_total}
          icon="hero-bolt"
          icon_class="text-accent-emerald"
        />
        <.stat_card
          label="Success Rate"
          value={success_rate_label(@metrics)}
          icon="hero-check-circle"
          icon_class="text-accent-emerald"
          color={if @metrics.error_rate > 10.0, do: "destructive"}
        />
        <.stat_card
          label="Avg Duration"
          value={format_duration(@metrics.avg_duration_ms)}
          icon="hero-clock"
          icon_class="text-accent-amber"
        />
      </.stat_grid>

      <section class="rounded-lg border bg-card p-4 shadow-sm">
        <h2 class="text-sm font-semibold mb-3">Top flows</h2>
        <%= if @metrics.top_flows == [] do %>
          <p class="text-sm text-muted-foreground">No flow activity in this period.</p>
        <% else %>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-xs uppercase text-muted-foreground border-b">
                <th class="py-2 font-medium">Flow</th>
                <th class="py-2 font-medium text-right">Executions</th>
                <th class="py-2 font-medium text-right">Error rate</th>
                <th class="py-2 font-medium text-right">Avg duration</th>
              </tr>
            </thead>
            <tbody class="divide-y">
              <tr :for={row <- @metrics.top_flows}>
                <td class="py-2 font-medium truncate">{row.flow_name}</td>
                <td class="py-2 text-right tabular-nums">{row.executions}</td>
                <td class={[
                  "py-2 text-right tabular-nums",
                  row.error_rate > 10.0 && "text-destructive"
                ]}>
                  {format_percentage(row.error_rate)}
                </td>
                <td class="py-2 text-right tabular-nums">
                  {format_duration(row.avg_duration_ms)}
                </td>
              </tr>
            </tbody>
          </table>
        <% end %>
      </section>
    </.page>
    """
  end

  @spec normalize_period(String.t() | nil) :: String.t()
  defp normalize_period(period) when period in @valid_periods, do: period
  defp normalize_period(_), do: @default_period

  @spec scope_subtitle(Scope.scope()) :: String.t()
  defp scope_subtitle({:project, _}), do: "Project flow executions"
  defp scope_subtitle({:org, _}), do: "Organization flow executions"

  @spec page_title(Scope.scope(), map(), map()) :: String.t()
  defp page_title({:project, _}, _org, %{name: name}), do: "#{name} Flows"
  defp page_title({:org, _}, %{name: name}, _project), do: "#{name} Flows"

  @spec success_rate_label(map()) :: String.t()
  defp success_rate_label(%{executions_total: 0}), do: "—"

  defp success_rate_label(%{error_rate: error_rate}) do
    success_rate = Float.round(100.0 - error_rate, 1)
    format_percentage(success_rate)
  end

  @spec format_percentage(float()) :: String.t()
  defp format_percentage(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 1) <> "%"

  @spec format_duration(float() | integer() | nil) :: String.t()
  defp format_duration(nil), do: "—"
  defp format_duration(ms) when is_integer(ms), do: "#{ms}ms"
  defp format_duration(ms) when is_float(ms), do: "#{:erlang.float_to_binary(ms, decimals: 1)}ms"
end
