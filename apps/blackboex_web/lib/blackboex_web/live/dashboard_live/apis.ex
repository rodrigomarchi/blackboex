defmodule BlackboexWeb.DashboardLive.Apis do
  @moduledoc """
  APIs tab of the dashboard. Renders aggregate API invocation metrics
  (totals, success rate, latency) and the top-10 APIs by invocations,
  scoped to either the current organization or the current project.

  The active period (`24h | 7d | 30d`) is read from the `?period=` query
  param and switched via `live_patch` (no remount).
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.StatCard

  alias Blackboex.Apis.DashboardQueries
  alias BlackboexWeb.DashboardLive.Scope

  @valid_periods ~w(24h 7d 30d)

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
         |> assign(:org, org)
         |> assign(:project, project)
         |> assign(:base_path, Scope.base_path(scope, org, project))
         |> assign(:page_title, page_title(scope, org, project))}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    period = normalize_period(params["period"])
    metrics = DashboardQueries.api_metrics(socket.assigns.scope, period)

    {:noreply,
     socket
     |> assign(:period, period)
     |> assign(:valid_periods, @valid_periods)
     |> assign(:metrics, metrics)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        Dashboard
        <:subtitle>{scope_subtitle(@scope)}</:subtitle>
        <:actions>
          <.dashboard_nav active={:apis} base_path={@base_path} />
        </:actions>
      </.header>

      <div class="flex items-center gap-2">
        <span class="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Period
        </span>
        <nav
          class="inline-flex h-9 items-center justify-center rounded-md bg-muted p-1 text-muted-foreground"
          aria-label="Period"
        >
          <.link
            :for={p <- @valid_periods}
            patch={"#{@base_path}/apis?period=#{p}"}
            class={[
              "inline-flex items-center justify-center rounded-sm px-3 py-1 text-xs font-medium transition-all",
              if(@period == p,
                do: "bg-background text-foreground shadow-sm",
                else: "hover:bg-background/50"
              )
            ]}
          >
            {p}
          </.link>
        </nav>
      </div>

      <.stat_grid cols="4">
        <.stat_card
          label="Invocations"
          value={@metrics.invocations_total}
          icon="hero-bolt"
          icon_class="text-accent-emerald"
        />
        <.stat_card
          label="Success Rate"
          value={"#{format_success_rate(@metrics)}%"}
          icon="hero-check-circle"
          icon_class="text-accent-emerald"
        />
        <.stat_card
          label="Avg Latency"
          value={format_ms(@metrics.avg_latency_ms)}
          icon="hero-clock"
          icon_class="text-accent-amber"
        />
        <.stat_card
          label="P95 Latency"
          value={format_ms(@metrics.p95_latency_ms)}
          icon="hero-chart-bar"
          icon_class="text-accent-violet"
        />
      </.stat_grid>

      <section class="rounded-lg border bg-card p-4 shadow-sm">
        <h2 class="text-sm font-semibold mb-3">Top APIs</h2>
        <%= if @metrics.top_apis == [] do %>
          <p class="text-sm text-muted-foreground">No APIs in this period.</p>
        <% else %>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-xs uppercase tracking-wide text-muted-foreground border-b">
                <th class="py-2 pr-3 font-medium">API</th>
                <th class="py-2 px-3 font-medium tabular-nums text-right">Invocations</th>
                <th class="py-2 px-3 font-medium tabular-nums text-right">Error rate</th>
                <th class="py-2 pl-3 font-medium tabular-nums text-right">Avg latency</th>
              </tr>
            </thead>
            <tbody class="divide-y">
              <tr :for={row <- @metrics.top_apis}>
                <td class="py-2 pr-3 font-medium truncate">{row.api_name}</td>
                <td class="py-2 px-3 tabular-nums text-right">{row.invocations}</td>
                <td class={[
                  "py-2 px-3 tabular-nums text-right",
                  error_rate_class(row.error_rate)
                ]}>
                  {row.error_rate}%
                </td>
                <td class="py-2 pl-3 tabular-nums text-right text-muted-foreground">
                  {format_ms(row.avg_latency_ms)}
                </td>
              </tr>
            </tbody>
          </table>
        <% end %>
      </section>
    </.page>
    """
  end

  defp normalize_period(p) when p in @valid_periods, do: p
  defp normalize_period(_), do: "24h"

  defp scope_subtitle({:project, _}), do: "Project APIs"
  defp scope_subtitle({:org, _}), do: "Organization APIs"

  defp page_title({:project, _}, _org, %{name: name}), do: "#{name} APIs"
  defp page_title({:project, _}, _org, _project), do: "Project APIs"
  defp page_title({:org, _}, %{name: name}, _project), do: "#{name} APIs"

  defp format_success_rate(%{invocations_total: 0}), do: "0.0"

  defp format_success_rate(%{invocations_total: total, invocations_success: success}) do
    Float.round(success / total * 100, 1)
  end

  defp format_ms(nil), do: "—"
  defp format_ms(ms) when is_number(ms), do: "#{round(ms)}ms"

  defp error_rate_class(rate) when is_number(rate) and rate >= 5.0, do: "text-destructive"
  defp error_rate_class(rate) when is_number(rate) and rate >= 1.0, do: "text-amber-600"
  defp error_rate_class(_), do: "text-muted-foreground"
end
