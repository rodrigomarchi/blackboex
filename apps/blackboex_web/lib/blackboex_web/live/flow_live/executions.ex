defmodule BlackboexWeb.FlowLive.Executions do
  @moduledoc """
  LiveView listing executions for a flow.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Shared.EmptyState
  import BlackboexWeb.Components.UI.SectionHeading
  import BlackboexWeb.FlowLive.ExecutionHelpers

  alias Blackboex.FlowExecutions
  alias Blackboex.Flows

  @impl true
  def mount(%{"id" => flow_id}, _session, socket) do
    org = socket.assigns.current_scope.organization

    case org && Flows.get_flow(org.id, flow_id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/flows")}

      flow ->
        executions = FlowExecutions.list_executions_for_flow(flow.id)
        stats = compute_stats(executions)

        {:ok,
         assign(socket,
           flow: flow,
           executions: executions,
           stats: stats,
           page_title: "Executions — #{flow.name}"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen flex-col overflow-hidden">
      <header class="flex h-12 shrink-0 items-center justify-between border-b bg-card px-4">
        <div class="flex items-center gap-3">
          <.link navigate={~p"/"} class="text-foreground hover:text-foreground/80">
            <.logo_icon class="size-7" />
          </.link>
          <.link
            navigate={~p"/flows/#{@flow.id}/edit"}
            class="link-muted"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <.section_heading level="h2" compact>Executions</.section_heading>
          <span class="text-xs text-muted-foreground">{@flow.name}</span>
        </div>
        <div :if={@executions != []} class="flex items-center gap-1.5 text-xs text-muted-foreground">
          <.icon name="hero-bolt-mini" class="size-3.5 text-accent-amber" />
          {length(@executions)} total runs
        </div>
      </header>

      <div class="flex-1 overflow-y-auto p-6 space-y-6">
        <%= if @executions != [] do %>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <.stat_mini
              label="Total"
              value={@stats.total}
              icon="hero-play-circle"
              color="text-accent-blue"
            />
            <.stat_mini
              label="Completed"
              value={@stats.completed}
              icon="hero-check-circle"
              color="text-accent-emerald"
            />
            <.stat_mini
              label="Failed"
              value={@stats.failed}
              icon="hero-x-circle"
              color="text-accent-red"
            />
            <.stat_mini
              label="Avg Duration"
              value={@stats.avg_duration}
              icon="hero-clock"
              color="text-accent-amber"
            />
          </div>
        <% end %>

        <%= if @executions == [] do %>
          <.empty_state
            icon="hero-clock"
            title="No executions yet"
            description="Trigger this flow via its webhook to see execution history here."
          />
        <% else %>
          <.card>
            <.card_content class="p-0">
              <.table
                id="flow-executions"
                rows={@executions}
                row_click={&JS.navigate(~p"/flows/#{@flow.id}/executions/#{&1.id}")}
              >
                <:col :let={exec} label="Status">
                  <div class={"inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium #{status_badge(exec.status)}"}>
                    <.icon name={status_icon(exec.status)} class="size-3.5" />
                    {exec.status}
                  </div>
                </:col>
                <:col :let={exec} label="Execution ID">
                  <span class="text-xs font-mono text-muted-foreground">
                    {short_id(exec.id)}
                  </span>
                </:col>
                <:col :let={exec} label="Duration">
                  <span class="text-xs font-mono">{format_duration(exec.duration_ms)}</span>
                </:col>
                <:col :let={exec} label="Started">
                  <span class="text-xs text-muted-foreground">
                    {format_time(exec.inserted_at)}
                  </span>
                </:col>
              </.table>
            </.card_content>
          </.card>
        <% end %>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "text-muted-foreground"

  defp stat_mini(assigns) do
    ~H"""
    <div class="flex items-center gap-3 rounded-lg border bg-card px-3 py-2.5">
      <.icon name={@icon} class={"size-4 #{@color}"} />
      <div>
        <div class="text-xs text-muted-foreground">{@label}</div>
        <div class="text-sm font-semibold">{@value}</div>
      </div>
    </div>
    """
  end

  @spec compute_stats(list()) :: map()
  defp compute_stats(executions) do
    total = length(executions)
    completed = Enum.count(executions, &(&1.status == "completed"))
    failed = Enum.count(executions, &(&1.status == "failed"))

    avg =
      executions
      |> Enum.map(& &1.duration_ms)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> "—"
        durations -> format_duration(div(Enum.sum(durations), length(durations)))
      end

    %{total: total, completed: completed, failed: failed, avg_duration: avg}
  end
end
