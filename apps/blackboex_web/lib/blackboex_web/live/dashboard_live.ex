defmodule BlackboexWeb.DashboardLive do
  @moduledoc """
  Main dashboard LiveView. Shows org summary, API stats, usage, and recent activity.
  """
  use BlackboexWeb, :live_view

  alias Blackboex.Apis.DashboardQueries
  alias Blackboex.Audit
  alias Blackboex.Billing.Enforcement

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization

    socket =
      if org do
        summary = DashboardQueries.get_org_summary(org.id)
        apis_with_stats = DashboardQueries.list_apis_with_stats(org.id)
        usage = Enforcement.get_usage_details(org)
        recent_activity = Audit.list_recent_activity(org.id, 5)

        assign(socket,
          summary: summary,
          apis_with_stats: apis_with_stats,
          usage: usage,
          recent_activity: recent_activity,
          page_title: "Dashboard"
        )
      else
        assign(socket,
          summary: %{total_apis: 0, calls_today: 0, errors_today: 0, avg_latency_today: nil},
          apis_with_stats: [],
          usage: nil,
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
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Dashboard</h1>
          <p class="text-muted-foreground">Overview of your workspace</p>
        </div>
        <.link
          :if={@apis_with_stats != []}
          navigate={~p"/apis/new"}
          class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Create API
        </.link>
      </div>

      <%= if @apis_with_stats == [] do %>
        <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm">
          <div class="flex flex-col items-center justify-center space-y-4 py-12">
            <.logo_icon class="size-12 text-muted-foreground" />
            <div class="text-center space-y-2">
              <h3 class="text-xl font-semibold">Welcome to BlackBoex</h3>
              <p class="text-sm text-muted-foreground max-w-md">
                Transform natural language into production-ready Elixir APIs.
                Create your first API to get started.
              </p>
            </div>
            <.link
              navigate={~p"/apis/new"}
              class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90"
            >
              Create your first API
            </.link>
          </div>
        </div>
      <% else %>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm text-muted-foreground">Total APIs</p>
            <p class="text-2xl font-bold">{@summary.total_apis}</p>
          </div>
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm text-muted-foreground">Calls Today</p>
            <p class="text-2xl font-bold">{@summary.calls_today}</p>
          </div>
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm text-muted-foreground">Errors Today</p>
            <p class="text-2xl font-bold">{@summary.errors_today}</p>
          </div>
          <div class="rounded-lg border bg-card p-4">
            <p class="text-sm text-muted-foreground">Plan</p>
            <p class="text-2xl font-bold">
              {format_plan(@usage)}
            </p>
          </div>
        </div>

        <div class="space-y-4">
          <h2 class="text-lg font-semibold">Your APIs</h2>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <.link
              :for={item <- @apis_with_stats}
              navigate={~p"/apis/#{item.api.id}"}
              class="block rounded-lg border bg-card p-4 text-card-foreground shadow-sm transition-colors hover:bg-accent"
            >
              <div class="flex items-center justify-between mb-2">
                <h3 class="font-semibold truncate">{item.api.name}</h3>
                <span class={[
                  "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                  status_color(item.api.status)
                ]}>
                  {item.api.status}
                </span>
              </div>
              <p :if={item.api.description} class="text-sm text-muted-foreground line-clamp-2 mb-3">
                {item.api.description}
              </p>
              <div class="flex items-center gap-4 text-xs text-muted-foreground">
                <span>{item.calls_24h} calls</span>
                <span>{format_latency(item.avg_latency)}</span>
                <span :if={item.errors_24h > 0} class="text-destructive">
                  {item.errors_24h} errors
                </span>
              </div>
            </.link>
          </div>
        </div>

        <div :if={@recent_activity != []} class="space-y-4">
          <h2 class="text-lg font-semibold">Recent Activity</h2>
          <div class="rounded-lg border bg-card divide-y">
            <div
              :for={activity <- @recent_activity}
              class="flex items-center justify-between px-4 py-3"
            >
              <span class="text-sm">{format_action(activity.action)}</span>
              <span class="text-xs text-muted-foreground">{relative_time(activity.timestamp)}</span>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @spec format_plan(map() | nil) :: String.t()
  defp format_plan(nil), do: "-"

  defp format_plan(%{plan: plan, apis: %{used: used, limit: :unlimited}}) do
    "#{format_plan_name(plan)} (#{used})"
  end

  defp format_plan(%{plan: plan, apis: %{used: used, limit: limit}}) do
    "#{format_plan_name(plan)} (#{used}/#{limit})"
  end

  @spec format_plan_name(atom() | String.t()) :: String.t()
  defp format_plan_name(plan) when is_atom(plan),
    do: plan |> Atom.to_string() |> String.capitalize()

  defp format_plan_name(plan) when is_binary(plan), do: String.capitalize(plan)

  @spec format_latency(float() | integer() | nil) :: String.t()
  defp format_latency(nil), do: "- ms"
  defp format_latency(ms) when is_float(ms), do: "#{Float.round(ms, 1)}ms"
  defp format_latency(ms) when is_integer(ms), do: "#{ms}ms"

  @spec status_color(String.t()) :: String.t()
  defp status_color("published"),
    do: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"

  defp status_color("compiled"),
    do: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300"

  defp status_color("draft"),
    do: "bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300"

  defp status_color("archived"),
    do: "bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400"

  defp status_color(_), do: "bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400"

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
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(dt, "%b %d")
    end
  end
end
