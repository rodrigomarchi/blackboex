defmodule BlackboexWeb.DashboardLive.Llm do
  @moduledoc """
  LLM tab of the dashboard. Renders aggregate LLM usage (generations,
  tokens, cost) and per-model + per-day breakdowns, scoped to either the
  current organization or the current project.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.StatCard
  import BlackboexWeb.Components.Shared.StatGrid
  alias Blackboex.Apis.DashboardQueries
  alias BlackboexWeb.DashboardLive.Scope

  @periods ~w(24h 7d 30d)
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
         |> assign(:page_title, "LLM Usage")
         |> assign(:scope, scope)
         |> assign(:base_path, Scope.base_path(scope, org, project))}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.scope
    period = normalize_period(params["period"])

    {:noreply,
     socket
     |> assign(:period, period)
     |> assign(:metrics, DashboardQueries.llm_metrics(scope, period))
     |> assign(:series, DashboardQueries.llm_usage_series(scope, period))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        Dashboard
        <:subtitle>{scope_subtitle(@scope)}</:subtitle>
        <:actions>
          <.dashboard_nav active={:llm} base_path={@base_path} />
        </:actions>
      </.header>

      <div class="flex items-center gap-2">
        <span class="text-xs text-muted-foreground uppercase tracking-wide">Period</span>
        <.link
          :for={p <- ~w(24h 7d 30d)}
          patch={"#{@base_path}/llm?period=#{p}"}
          class={[
            "rounded-md border px-2 py-1 text-xs font-medium",
            if(@period == p,
              do: "bg-primary text-primary-foreground border-primary",
              else: "bg-card text-muted-foreground hover:bg-muted"
            )
          ]}
        >
          {p}
        </.link>
      </div>

      <.stat_grid cols="4">
        <.stat_card
          label="Generations"
          value={@metrics.total_generations}
          icon="hero-sparkles"
          icon_class="text-accent-violet"
        />
        <.stat_card
          label="Tokens (in / out)"
          value={"#{@metrics.total_tokens_input} / #{@metrics.total_tokens_output}"}
          icon="hero-arrow-down-on-square"
          icon_class="text-accent-amber"
        />
        <.stat_card
          label="Estimated cost"
          value={format_cents(@metrics.estimated_cost_cents)}
          icon="hero-currency-dollar"
          icon_class="text-accent-emerald"
        />
        <.stat_card
          label="Avg cost / generation"
          value={
            format_cents(avg_cost_cents(@metrics.estimated_cost_cents, @metrics.total_generations))
          }
          icon="hero-calculator"
          icon_class="text-muted-foreground"
        />
      </.stat_grid>

      <section class="rounded-lg border bg-card p-4 shadow-sm">
        <h2 class="text-sm font-semibold mb-3">By model</h2>
        <%= if @metrics.by_model == [] do %>
          <p class="text-sm text-muted-foreground">No model usage in this period.</p>
        <% else %>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-xs text-muted-foreground uppercase tracking-wide">
                <th class="py-2 pr-4">Model</th>
                <th class="py-2 pr-4 text-right">Generations</th>
                <th class="py-2 pr-4 text-right">Tokens</th>
                <th class="py-2 pr-4 text-right">Cost</th>
              </tr>
            </thead>
            <tbody class="divide-y">
              <tr :for={row <- @metrics.by_model} class="text-sm">
                <td class="py-2 pr-4 font-mono">{row.model}</td>
                <td class="py-2 pr-4 text-right tabular-nums">{row.generations}</td>
                <td class="py-2 pr-4 text-right tabular-nums">{row.tokens}</td>
                <td class="py-2 pr-4 text-right tabular-nums">{format_cents(row.cost_cents)}</td>
              </tr>
            </tbody>
          </table>
        <% end %>
      </section>

      <section class="rounded-lg border bg-card p-4 shadow-sm">
        <h2 class="text-sm font-semibold mb-3">Daily series</h2>
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs text-muted-foreground uppercase tracking-wide">
              <th class="py-2 pr-4">Date</th>
              <th class="py-2 pr-4 text-right">Generations</th>
              <th class="py-2 pr-4 text-right">Tokens</th>
              <th class="py-2 pr-4 text-right">Cost</th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={row <- @series} class="text-sm">
              <td class="py-2 pr-4 font-mono">{Calendar.strftime(row.date, "%Y-%m-%d")}</td>
              <td class="py-2 pr-4 text-right tabular-nums">{row.generations}</td>
              <td class="py-2 pr-4 text-right tabular-nums">{row.tokens}</td>
              <td class="py-2 pr-4 text-right tabular-nums">{format_cents(row.cost_cents)}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </.page>
    """
  end

  @spec normalize_period(String.t() | nil) :: String.t()
  defp normalize_period(p) when p in @periods, do: p
  defp normalize_period(_), do: @default_period

  @spec format_cents(integer() | nil) :: String.t()
  defp format_cents(nil), do: "$0.00"

  defp format_cents(cents) when is_integer(cents),
    do: :io_lib.format("$~.2f", [cents / 100]) |> IO.iodata_to_binary()

  @spec avg_cost_cents(integer(), integer()) :: integer()
  defp avg_cost_cents(_cost, 0), do: 0
  defp avg_cost_cents(cost, generations), do: div(cost, generations)

  defp scope_subtitle({:project, _}), do: "Project LLM usage"
  defp scope_subtitle({:org, _}), do: "Organization LLM usage"
end
