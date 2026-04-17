defmodule BlackboexWeb.DashboardLive.Overview do
  @moduledoc """
  Overview tab of the dashboard. Renders aggregate counts and recent
  activity, scoped to either the current organization or the current
  project depending on the URL.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.StatCard

  alias Blackboex.Apis.DashboardQueries
  alias BlackboexWeb.DashboardLive.Scope

  @impl true
  def mount(params, _session, socket) do
    case Scope.from_socket(socket, params) do
      nil ->
        {:ok, push_navigate(socket, to: "/")}

      scope ->
        current = socket.assigns.current_scope
        org = current.organization
        project = current.project
        summary = DashboardQueries.overview_summary(scope)

        {:ok,
         socket
         |> assign(:page_title, page_title(scope, org, project))
         |> assign(:scope, scope)
         |> assign(:base_path, Scope.base_path(scope, org, project))
         |> assign(:summary, summary)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        Dashboard
        <:subtitle>{scope_subtitle(@scope)}</:subtitle>
        <:actions>
          <.dashboard_nav active={:overview} base_path={@base_path} />
        </:actions>
      </.header>

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
                {format_duration(entry.duration_ms)}
              </span>
            </li>
          </ul>
        <% end %>
      </section>
    </.page>
    """
  end

  defp scope_subtitle({:project, _}), do: "Project overview"
  defp scope_subtitle({:org, _}), do: "Organization overview"

  defp page_title({:project, _}, _org, project),
    do: "#{(project && project.name) || "Project"} Dashboard"

  defp page_title({:org, _}, org, _project),
    do: "#{(org && org.name) || "Org"} Dashboard"

  defp status_badge_class(code) when is_integer(code) and code >= 500,
    do: "bg-destructive/15 text-destructive"

  defp status_badge_class(code) when is_integer(code) and code >= 400,
    do: "bg-amber-500/15 text-amber-600"

  defp status_badge_class(code) when is_integer(code) and code >= 300,
    do: "bg-blue-500/15 text-blue-600"

  defp status_badge_class(_), do: "bg-emerald-500/15 text-emerald-600"

  defp format_duration(nil), do: "—"
  defp format_duration(ms) when is_integer(ms), do: "#{ms}ms"
end
