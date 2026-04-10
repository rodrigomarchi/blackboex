defmodule BlackboexWeb.DashboardLive do
  @moduledoc """
  Dashboard overview page. Shows big-number summary stats and recent activity.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.StatCard
  import BlackboexWeb.Components.Shared.EmptyState
  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.DashboardHelpers
  import BlackboexWeb.Components.Card

  alias Blackboex.Apis.DashboardQueries
  alias Blackboex.Audit

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization

    socket =
      if org do
        load_overview(socket, org)
      else
        assign(socket,
          summary: empty_summary(),
          recent_activity: [],
          page_title: "Dashboard"
        )
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-home" class="size-5 text-sky-400" /> Dashboard
        </span>
        <:subtitle>Overview of your workspace</:subtitle>
        <:actions>
          <.dashboard_nav active="overview" />
        </:actions>
      </.header>

      <%= if @summary.total_apis == 0 and @summary.total_flows == 0 do %>
        <.empty_state
          title="Welcome to BlackBoex"
          description="Transform natural language into production-ready Elixir APIs. Create your first API to get started."
          icon="hero-rocket-launch"
          icon_class="text-violet-400"
        >
          <:actions>
            <.button navigate={~p"/apis/new"} variant="primary">
              <.icon name="hero-plus" class="mr-1.5 size-3.5 text-emerald-300" />
              Create your first API
            </.button>
          </:actions>
        </.empty_state>
      <% else %>
        <%!-- Big number stat cards --%>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.stat_card
            label="Total APIs"
            value={format_number(@summary.total_apis)}
            icon="hero-cube-mini"
            icon_class="text-blue-400"
          />
          <.stat_card
            label="Total Flows"
            value={format_number(@summary.total_flows)}
            icon="hero-arrow-path-mini"
            icon_class="text-violet-400"
          />
          <.stat_card
            label="API Keys"
            value={format_number(@summary.total_api_keys)}
            icon="hero-key-mini"
            icon_class="text-amber-400"
          />
          <.stat_card
            label="Active APIs"
            value={format_number(@summary.active_apis)}
            icon="hero-signal-mini"
            icon_class="text-emerald-400"
          />
          <.stat_card
            label="Active Flows"
            value={format_number(@summary.active_flows)}
            icon="hero-play-mini"
            icon_class="text-sky-400"
          />
          <.stat_card
            label="Executions Today"
            value={format_number(@summary.total_executions_today)}
            icon="hero-bolt-mini"
            icon_class="text-orange-400"
          />
          <.stat_card
            label="Conversations"
            value={format_number(@summary.total_conversations)}
            icon="hero-chat-bubble-left-right-mini"
            icon_class="text-indigo-400"
          />
          <.stat_card
            label="Errors Today"
            value={format_number(@summary.errors_today)}
            icon="hero-exclamation-circle-mini"
            icon_class="text-red-400"
          />
          <.stat_card
            label="LLM Cost (month)"
            value={format_cost(@summary.llm_cost_month_cents)}
            icon="hero-currency-dollar-mini"
            icon_class="text-emerald-400"
          />
        </div>

        <%!-- Recent Activity --%>
        <.card>
          <.card_content class="p-4">
            <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
              <.icon name="hero-clock-mini" class="size-3.5 text-amber-400" /> Recent Activity
            </p>
            <div :if={@recent_activity == []} class="py-4 text-center text-sm text-muted-foreground">
              No recent activity
            </div>
            <div :if={@recent_activity != []} class="divide-y">
              <div
                :for={activity <- @recent_activity}
                class="flex items-center justify-between py-2"
              >
                <span class="text-sm">{format_action(activity.action)}</span>
                <span class="text-xs text-muted-foreground">
                  {relative_time(activity.timestamp)}
                </span>
              </div>
            </div>
          </.card_content>
        </.card>
      <% end %>
    </div>
    """
  end

  # -- Data loading --

  defp load_overview(socket, org) do
    summary = DashboardQueries.get_overview_summary(org.id)
    recent_activity = Audit.list_recent_activity(org.id, 10)

    assign(socket,
      summary: summary,
      recent_activity: recent_activity,
      page_title: "Dashboard"
    )
  end

  defp empty_summary do
    %{
      total_apis: 0,
      total_flows: 0,
      total_api_keys: 0,
      active_apis: 0,
      active_flows: 0,
      total_executions_today: 0,
      total_conversations: 0,
      llm_cost_month_cents: 0,
      errors_today: 0
    }
  end

  # -- Template helpers --

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
end
