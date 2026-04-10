defmodule BlackboexWeb.DashboardLlmLive do
  @moduledoc """
  Dashboard LLM tab. Shows LLM usage by model/provider, cost breakdown,
  conversation stats, and agent run metrics.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.Charts
  import BlackboexWeb.Components.Shared.StatCard
  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.DashboardHelpers
  import BlackboexWeb.Components.Card

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
    <div class="space-y-6">
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-sparkles" class="size-5 text-violet-400" /> LLM Metrics
        </span>
        <:subtitle>AI model usage, costs, and performance</:subtitle>
        <:actions>
          <div class="flex items-center gap-3">
            <.dashboard_nav active="llm" />
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
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <.stat_card
          label={"LLM Calls (#{period_label(@period)})"}
          value={format_number(@metrics.total_calls)}
          icon="hero-sparkles-mini"
          icon_class="text-violet-400"
        />
        <.stat_card
          label={"Total Cost (#{period_label(@period)})"}
          value={format_cost(@metrics.total_cost_cents)}
          icon="hero-currency-dollar-mini"
          icon_class="text-amber-400"
        />
        <.stat_card
          label={"Tokens In (#{period_label(@period)})"}
          value={format_tokens(@metrics.total_input_tokens)}
          icon="hero-arrow-down-tray-mini"
          icon_class="text-blue-400"
        />
        <.stat_card
          label={"Tokens Out (#{period_label(@period)})"}
          value={format_tokens(@metrics.total_output_tokens)}
          icon="hero-arrow-up-tray-mini"
          icon_class="text-emerald-400"
        />
        <.stat_card
          label={"Avg Duration (#{period_label(@period)})"}
          value={format_duration(@metrics.avg_duration_ms)}
          icon="hero-clock-mini"
          icon_class="text-sky-400"
        />
      </div>

      <%!-- Charts --%>
      <div class="grid gap-4 lg:grid-cols-2">
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-sparkles-mini" class="size-3.5 text-violet-400" /> LLM Calls
            </p>
            <.bar_chart data={@metrics.calls_series} color="var(--color-chart-4)" />
          </.card_content>
        </.card>
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-currency-dollar-mini" class="size-3.5 text-amber-400" /> Cost (cents)
            </p>
            <.line_chart data={@metrics.cost_series} color="var(--color-chart-5)" />
          </.card_content>
        </.card>
      </div>

      <div class="grid gap-4 lg:grid-cols-2">
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-arrow-down-tray-mini" class="size-3.5 text-blue-400" /> Tokens
            </p>
            <.bar_chart data={@metrics.tokens_series} />
          </.card_content>
        </.card>
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-clock-mini" class="size-3.5 text-sky-400" /> Avg Duration (ms)
            </p>
            <.line_chart data={@metrics.duration_series} color="var(--color-chart-3)" />
          </.card_content>
        </.card>
      </div>

      <%!-- Usage by Model table --%>
      <.card :if={@metrics.by_model != []}>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-cpu-chip-mini" class="size-3.5 text-violet-400" /> Usage by Model
          </p>
          <.table id="by-model" rows={@metrics.by_model}>
            <:col :let={row} label="Provider">{row.provider}</:col>
            <:col :let={row} label="Model">{row.model}</:col>
            <:col :let={row} label="Calls">{format_number(row.calls)}</:col>
            <:col :let={row} label="Tokens In">{format_tokens(row.input_tokens)}</:col>
            <:col :let={row} label="Tokens Out">{format_tokens(row.output_tokens)}</:col>
            <:col :let={row} label="Cost">{format_cost(row.cost_cents)}</:col>
            <:col :let={row} label="Avg Duration">{format_duration(row.avg_duration_ms)}</:col>
          </.table>
        </.card_content>
      </.card>

      <%!-- Usage by Operation --%>
      <.card :if={@metrics.by_operation != []}>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-cog-6-tooth-mini" class="size-3.5 text-sky-400" /> Usage by Operation
          </p>
          <.table id="by-operation" rows={@metrics.by_operation}>
            <:col :let={row} label="Operation">{format_operation(row.operation)}</:col>
            <:col :let={row} label="Calls">{format_number(row.calls)}</:col>
            <:col :let={row} label="Cost">{format_cost(row.cost_cents)}</:col>
            <:col :let={row} label="Avg Duration">{format_duration(row.avg_duration_ms)}</:col>
          </.table>
        </.card_content>
      </.card>

      <%!-- Cost by API --%>
      <.card :if={@metrics.cost_by_api != []}>
        <.card_content class="p-4">
          <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
            <.icon name="hero-cube-mini" class="size-3.5 text-blue-400" /> Cost by API
          </p>
          <.table id="cost-by-api" rows={@metrics.cost_by_api}>
            <:col :let={row} label="API">{row.api_name}</:col>
            <:col :let={row} label="Calls">{format_number(row.calls)}</:col>
            <:col :let={row} label="Tokens In">{format_tokens(row.input_tokens)}</:col>
            <:col :let={row} label="Tokens Out">{format_tokens(row.output_tokens)}</:col>
            <:col :let={row} label="Cost">{format_cost(row.cost_cents)}</:col>
          </.table>
        </.card_content>
      </.card>

      <%!-- Conversations & Runs summary --%>
      <div class="grid gap-4 lg:grid-cols-2">
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-chat-bubble-left-right-mini" class="size-3.5 text-indigo-400" />
              Conversations
            </p>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <p class="text-2xl font-bold">{format_number(@metrics.conversations.total)}</p>
                <p class="text-xs text-muted-foreground">Total</p>
              </div>
              <div>
                <p class="text-2xl font-bold text-emerald-400">
                  {format_number(@metrics.conversations.active)}
                </p>
                <p class="text-xs text-muted-foreground">Active</p>
              </div>
              <div>
                <p class="text-2xl font-bold">{format_tokens(@metrics.conversations.total_tokens)}</p>
                <p class="text-xs text-muted-foreground">Total Tokens</p>
              </div>
              <div>
                <p class="text-2xl font-bold">
                  {format_cost(@metrics.conversations.total_cost_cents)}
                </p>
                <p class="text-xs text-muted-foreground">Total Cost</p>
              </div>
            </div>
          </.card_content>
        </.card>
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-play-mini" class="size-3.5 text-sky-400" />
              Agent Runs ({period_label(@period)})
            </p>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <p class="text-2xl font-bold">{format_number(@metrics.runs.total)}</p>
                <p class="text-xs text-muted-foreground">Total</p>
              </div>
              <div>
                <p class="text-2xl font-bold text-emerald-400">
                  {format_number(@metrics.runs.completed)}
                </p>
                <p class="text-xs text-muted-foreground">Completed</p>
              </div>
              <div>
                <p class="text-2xl font-bold text-red-400">{format_number(@metrics.runs.failed)}</p>
                <p class="text-xs text-muted-foreground">Failed</p>
              </div>
              <div>
                <p class="text-2xl font-bold">{format_duration(@metrics.runs.avg_duration_ms)}</p>
                <p class="text-xs text-muted-foreground">Avg Duration</p>
              </div>
            </div>
          </.card_content>
        </.card>
      </div>
    </div>
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
