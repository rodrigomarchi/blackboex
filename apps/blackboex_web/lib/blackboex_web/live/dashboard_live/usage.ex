defmodule BlackboexWeb.DashboardLive.Usage do
  @moduledoc """
  Usage tab of the dashboard. Renders billing usage metrics — API
  invocations, LLM generations, token totals and cost — sourced from the
  `daily_usage` rollup table for the daily series and from `usage_events`
  for the by-event-type breakdown. Scoped to either the current
  organization or the current project depending on the URL.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.PeriodSelector
  import BlackboexWeb.Components.Shared.StatCard

  alias Blackboex.Apis.DashboardQueries
  alias BlackboexWeb.DashboardLive.Scope

  @valid_periods ~w(24h 7d 30d)
  @default_period "30d"

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
    metrics = DashboardQueries.usage_metrics(socket.assigns.scope, period)

    {:noreply,
     socket
     |> assign(:period, period)
     |> assign(:metrics, metrics)}
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) do
    period = normalize_period(period)

    {:noreply, push_patch(socket, to: socket.assigns.base_path <> "/usage?period=" <> period)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        Usage
        <:subtitle>{scope_subtitle(@scope)}</:subtitle>
        <:actions>
          <.dashboard_nav active={:usage} base_path={@base_path} />
        </:actions>
      </.header>

      <div class="flex justify-end">
        <.period_selector period={@period} />
      </div>

      <.stat_grid cols="4">
        <.stat_card
          label="API invocations"
          value={@metrics.totals.api_invocations}
          icon="hero-bolt"
          icon_class="text-accent-emerald"
        />
        <.stat_card
          label="LLM generations"
          value={@metrics.totals.llm_generations}
          icon="hero-sparkles"
          icon_class="text-accent-violet"
        />
        <.stat_card
          label="Tokens (in / out)"
          value={format_tokens(@metrics.totals)}
          icon="hero-square-3-stack-3d"
          icon_class="text-accent-amber"
        />
        <.stat_card
          label="LLM cost"
          value={format_cost(@metrics.totals.llm_cost_cents)}
          icon="hero-currency-dollar"
          icon_class="text-accent-emerald"
        />
      </.stat_grid>

      <section class="rounded-lg border bg-card p-4 shadow-sm">
        <h2 class="text-sm font-semibold mb-3">Daily series</h2>
        <%= if @metrics.daily_series == [] do %>
          <p class="text-sm text-muted-foreground">No usage in this period.</p>
        <% else %>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-xs uppercase text-muted-foreground border-b">
                <th class="py-2 font-medium">Date</th>
                <th class="py-2 font-medium text-right">Invocations</th>
                <th class="py-2 font-medium text-right">Generations</th>
                <th class="py-2 font-medium text-right">Tokens</th>
                <th class="py-2 font-medium text-right">Cost</th>
              </tr>
            </thead>
            <tbody class="divide-y">
              <tr :for={row <- @metrics.daily_series}>
                <td class="py-2 font-mono text-xs">{format_date(row.date)}</td>
                <td class="py-2 text-right tabular-nums">{row.api_invocations}</td>
                <td class="py-2 text-right tabular-nums">{row.llm_generations}</td>
                <td class="py-2 text-right tabular-nums">
                  {row.tokens_input + row.tokens_output}
                </td>
                <td class="py-2 text-right tabular-nums">
                  {format_cost(row.llm_cost_cents)}
                </td>
              </tr>
            </tbody>
          </table>
        <% end %>
      </section>

      <section class="rounded-lg border bg-card p-4 shadow-sm">
        <h2 class="text-sm font-semibold mb-3">By event type</h2>
        <%= if @metrics.by_event_type == [] do %>
          <p class="text-sm text-muted-foreground">No events recorded in this period.</p>
        <% else %>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-xs uppercase text-muted-foreground border-b">
                <th class="py-2 font-medium">Event type</th>
                <th class="py-2 font-medium text-right">Count</th>
              </tr>
            </thead>
            <tbody class="divide-y">
              <tr :for={row <- @metrics.by_event_type}>
                <td class="py-2 font-mono text-xs">{row.event_type}</td>
                <td class="py-2 text-right tabular-nums">{row.count}</td>
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
  defp scope_subtitle({:project, _}), do: "Project usage"
  defp scope_subtitle({:org, _}), do: "Organization usage"

  @spec page_title(Scope.scope(), map() | nil, map() | nil) :: String.t()
  defp page_title({:project, _}, _org, %{name: name}), do: "#{name} Usage"
  defp page_title({:org, _}, %{name: name}, _project), do: "#{name} Usage"

  @spec format_tokens(map()) :: String.t()
  defp format_tokens(%{tokens_input: input, tokens_output: output}) do
    "#{format_int(input)} / #{format_int(output)}"
  end

  @spec format_int(integer()) :: String.t()
  defp format_int(n) when is_integer(n), do: Integer.to_string(n)

  @spec format_cost(integer()) :: String.t()
  defp format_cost(cents) when is_integer(cents) do
    dollars = cents / 100
    "$" <> :erlang.float_to_binary(dollars, decimals: 2)
  end

  @spec format_date(Date.t()) :: String.t()
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d")
end
