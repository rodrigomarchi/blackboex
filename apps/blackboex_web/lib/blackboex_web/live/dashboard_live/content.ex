defmodule BlackboexWeb.DashboardLive.Content do
  @moduledoc """
  Function components for each dashboard tab.
  Renders the data sections without page/header wrappers.
  Used by OrgSettingsLive and ProjectSettingsLive.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Shared.StatCard

  @valid_periods ~w(24h 7d 30d)

  attr :summary, :map, required: true

  @spec overview_content(map()) :: Phoenix.LiveView.Rendered.t()
  def overview_content(assigns) do
    ~H"""
    <.stat_grid cols="4">
      <.stat_card
        label="Total APIs"
        value={@summary.total_apis}
        icon="hero-cube"
        icon_class="text-accent-amber"
      />
      <.stat_card
        label="Total Flows"
        value={@summary.total_flows}
        icon="hero-arrow-path"
        icon_class="text-accent-violet"
      />
      <.stat_card
        label="Invocations (24h)"
        value={@summary.invocations_24h}
        icon="hero-bolt"
        icon_class="text-accent-emerald"
      />
      <.stat_card
        label="Errors (24h)"
        value={@summary.errors_24h}
        color={if @summary.errors_24h > 0, do: "destructive"}
        icon="hero-exclamation-triangle"
        icon_class="text-destructive"
      />
    </.stat_grid>

    <section class="rounded-lg border bg-card p-4 shadow-sm">
      <h2 class="text-sm font-semibold mb-3">Recent activity</h2>
      <%= if @summary.recent_activity == [] do %>
        <p class="text-sm text-muted-foreground">No invocations in the last 24h.</p>
      <% else %>
        <ul class="divide-y">
          <li
            :for={entry <- @summary.recent_activity}
            class="flex items-center gap-3 py-2 text-sm"
          >
            <span class={[
              "inline-flex h-5 min-w-[2.5rem] items-center justify-center rounded px-1.5 text-[11px] font-mono font-semibold",
              status_badge_class(entry.status_code)
            ]}>
              {entry.status_code}
            </span>
            <span class="font-mono text-xs text-muted-foreground">{entry.method}</span>
            <span class="font-medium truncate">{entry.api_name || "—"}</span>
            <span class="font-mono text-xs text-muted-foreground truncate flex-1">
              {entry.path}
            </span>
            <span class="text-xs text-muted-foreground tabular-nums">
              {format_duration_ms(entry.duration_ms)}
            </span>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  attr :metrics, :map, required: true
  attr :period, :string, required: true
  attr :base_path, :string, required: true

  @spec apis_content(map()) :: Phoenix.LiveView.Rendered.t()
  def apis_content(assigns) do
    assigns = assign(assigns, :valid_periods, @valid_periods)

    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-xs font-medium uppercase tracking-wide text-muted-foreground">Period</span>
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
              <td class={["py-2 px-3 tabular-nums text-right", error_rate_class(row.error_rate)]}>
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
    """
  end

  attr :metrics, :map, required: true
  attr :period, :string, required: true
  attr :base_path, :string, required: true

  @spec flows_content(map()) :: Phoenix.LiveView.Rendered.t()
  def flows_content(assigns) do
    assigns = assign(assigns, :valid_periods, @valid_periods)

    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-xs font-medium uppercase tracking-wide text-muted-foreground">Period</span>
      <nav
        class="inline-flex h-9 items-center justify-center rounded-md bg-muted p-1 text-muted-foreground"
        aria-label="Period"
      >
        <.link
          :for={p <- @valid_periods}
          patch={"#{@base_path}/flows?period=#{p}"}
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
        value={flows_success_rate(@metrics)}
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
              <td class="py-2 text-right tabular-nums">{format_duration(row.avg_duration_ms)}</td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </section>
    """
  end

  attr :metrics, :map, required: true
  attr :series, :list, required: true
  attr :period, :string, required: true
  attr :base_path, :string, required: true

  @spec llm_content(map()) :: Phoenix.LiveView.Rendered.t()
  def llm_content(assigns) do
    ~H"""
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
    """
  end

  attr :metrics, :map, required: true
  attr :period, :string, required: true
  attr :base_path, :string, required: true

  @spec usage_content(map()) :: Phoenix.LiveView.Rendered.t()
  def usage_content(assigns) do
    assigns = assign(assigns, :valid_periods, @valid_periods)

    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-xs font-medium uppercase tracking-wide text-muted-foreground">Period</span>
      <nav
        class="inline-flex h-9 items-center justify-center rounded-md bg-muted p-1 text-muted-foreground"
        aria-label="Period"
      >
        <.link
          :for={p <- @valid_periods}
          patch={"#{@base_path}/usage?period=#{p}"}
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
        value={format_token_pair(@metrics.totals)}
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
              <td class="py-2 text-right tabular-nums">{row.tokens_input + row.tokens_output}</td>
              <td class="py-2 text-right tabular-nums">{format_cost(row.llm_cost_cents)}</td>
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
    """
  end

  defp status_badge_class(code) when is_integer(code) and code >= 500,
    do: "bg-destructive/15 text-destructive"

  defp status_badge_class(code) when is_integer(code) and code >= 400,
    do: "bg-amber-500/15 text-amber-600"

  defp status_badge_class(code) when is_integer(code) and code >= 300,
    do: "bg-blue-500/15 text-blue-600"

  defp status_badge_class(_), do: "bg-emerald-500/15 text-emerald-600"

  defp format_duration_ms(nil), do: "—"
  defp format_duration_ms(ms) when is_integer(ms), do: "#{ms}ms"

  defp format_success_rate(%{invocations_total: 0}), do: "0.0"

  defp format_success_rate(%{invocations_total: total, invocations_success: success}),
    do: Float.round(success / total * 100, 1)

  defp format_ms(nil), do: "—"
  defp format_ms(ms) when is_number(ms), do: "#{round(ms)}ms"

  defp error_rate_class(rate) when is_number(rate) and rate >= 5.0, do: "text-destructive"
  defp error_rate_class(rate) when is_number(rate) and rate >= 1.0, do: "text-amber-600"
  defp error_rate_class(_), do: "text-muted-foreground"

  defp flows_success_rate(%{executions_total: 0}), do: "—"

  defp flows_success_rate(%{error_rate: error_rate}),
    do: format_percentage(Float.round(100.0 - error_rate, 1))

  defp format_percentage(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 1) <> "%"

  defp format_duration(nil), do: "—"
  defp format_duration(ms) when is_integer(ms), do: "#{ms}ms"

  defp format_duration(ms) when is_float(ms),
    do: "#{:erlang.float_to_binary(ms, decimals: 1)}ms"

  defp format_cents(nil), do: "$0.00"

  defp format_cents(cents) when is_integer(cents),
    do: :io_lib.format("$~.2f", [cents / 100]) |> IO.iodata_to_binary()

  defp avg_cost_cents(_cost, 0), do: 0
  defp avg_cost_cents(cost, generations), do: div(cost, generations)

  defp format_token_pair(%{tokens_input: input, tokens_output: output}),
    do: "#{input} / #{output}"

  defp format_cost(cents) when is_integer(cents),
    do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d")
end
