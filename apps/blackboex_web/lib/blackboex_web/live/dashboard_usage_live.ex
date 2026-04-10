defmodule BlackboexWeb.DashboardUsageLive do
  @moduledoc """
  Dashboard Usage tab. Shows LLM generations, tokens, costs, and API invocations from daily_usage.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.Charts
  import BlackboexWeb.Components.Shared.StatCard
  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.DashboardHelpers
  import BlackboexWeb.Components.Shared.ProgressBar
  import BlackboexWeb.Components.Card

  alias Blackboex.Apis.DashboardQueries
  alias Blackboex.Billing.Enforcement

  @valid_periods ~w(24h 7d 30d)

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    period = "30d"

    socket =
      if org do
        load_usage(socket, org, period)
      else
        assign(socket,
          metrics: empty_metrics(),
          usage: nil,
          period: period,
          page_title: "Dashboard - Usage"
        )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) when period in @valid_periods do
    org = socket.assigns.current_scope.organization

    if org do
      metrics = DashboardQueries.get_usage_metrics(org.id, period)
      {:noreply, assign(socket, metrics: metrics, period: period)}
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
          <.icon name="hero-chart-bar" class="size-5 text-emerald-400" /> Usage
        </span>
        <:subtitle>Resource consumption and billing metrics</:subtitle>
        <:actions>
          <div class="flex items-center gap-3">
            <.dashboard_nav active="usage" />
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
          label={"API Invocations (#{period_label(@period)})"}
          value={format_number(@metrics.api_invocations_total)}
          icon="hero-signal-mini"
          icon_class="text-sky-400"
        />
        <.stat_card
          label={"LLM Generations (#{period_label(@period)})"}
          value={format_number(@metrics.llm_generations_total)}
          icon="hero-sparkles-mini"
          icon_class="text-violet-400"
        />
        <.stat_card
          label={"Total Tokens (#{period_label(@period)})"}
          value={format_tokens(@metrics.tokens_in_total + @metrics.tokens_out_total)}
          icon="hero-calculator-mini"
          icon_class="text-blue-400"
        />
        <.stat_card
          label={"LLM Cost (#{period_label(@period)})"}
          value={"$#{Float.round(@metrics.cost_total_cents / 100, 2)}"}
          icon="hero-currency-dollar-mini"
          icon_class="text-amber-400"
        />
      </div>

      <%!-- Plan limits --%>
      <.card :if={@usage}>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-4">
            <.icon name="hero-shield-check-mini" class="size-3.5 text-emerald-400" /> Plan Limits
          </p>
          <div class="space-y-3">
            <.progress_bar
              label="LLM Generations (month)"
              used={format_number(llm_gens_used(@usage))}
              limit={format_llm_limit(@usage)}
              percentage={llm_gens_pct(@usage)}
            />
          </div>
        </.card_content>
      </.card>

      <%!-- Charts --%>
      <div class="grid gap-4 lg:grid-cols-2">
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-signal-mini" class="size-3.5 text-sky-400" /> API Invocations
            </p>
            <.bar_chart data={@metrics.api_invocations_series} />
          </.card_content>
        </.card>
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-sparkles-mini" class="size-3.5 text-violet-400" /> LLM Generations
            </p>
            <.bar_chart data={@metrics.generations_series} color="var(--color-chart-4)" />
          </.card_content>
        </.card>
      </div>

      <div class="grid gap-4 lg:grid-cols-2">
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-arrow-down-tray-mini" class="size-3.5 text-blue-400" /> Tokens In
            </p>
            <.line_chart data={@metrics.tokens_in_series} />
          </.card_content>
        </.card>
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-arrow-up-tray-mini" class="size-3.5 text-emerald-400" /> Tokens Out
            </p>
            <.line_chart data={@metrics.tokens_out_series} color="var(--color-chart-3)" />
          </.card_content>
        </.card>
      </div>

      <.card>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-currency-dollar-mini" class="size-3.5 text-amber-400" /> LLM Cost ($)
          </p>
          <.line_chart data={@metrics.cost_series} color="var(--color-chart-5)" />
        </.card_content>
      </.card>
    </div>
    """
  end

  # -- Data loading --

  defp load_usage(socket, org, period) do
    metrics = DashboardQueries.get_usage_metrics(org.id, period)
    usage = Enforcement.get_usage_details(org)

    assign(socket,
      metrics: metrics,
      usage: usage,
      period: period,
      page_title: "Dashboard - Usage"
    )
  end

  defp empty_metrics do
    %{
      api_invocations_series: [],
      api_invocations_total: 0,
      generations_series: [],
      llm_generations_total: 0,
      tokens_in_series: [],
      tokens_out_series: [],
      tokens_in_total: 0,
      tokens_out_total: 0,
      cost_series: [],
      cost_total_cents: 0
    }
  end

  # -- Template helpers --

  @spec llm_gens_used(map() | nil) :: non_neg_integer()
  defp llm_gens_used(nil), do: 0
  defp llm_gens_used(%{llm_generations_month: %{used: used}}), do: used

  @spec llm_gens_pct(map() | nil) :: float()
  defp llm_gens_pct(nil), do: 0.0
  defp llm_gens_pct(%{llm_generations_month: %{pct: pct}}), do: pct

  @spec format_llm_limit(map() | nil) :: String.t()
  defp format_llm_limit(nil), do: "-"
  defp format_llm_limit(%{llm_generations_month: %{limit: :unlimited}}), do: "unlimited"
  defp format_llm_limit(%{llm_generations_month: %{limit: limit}}), do: format_number(limit)
end
