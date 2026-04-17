defmodule BlackboexWeb.OrgDashboardLive do
  @moduledoc """
  Organization-level dashboard.

  Shows aggregated stats across all projects in the org.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.StatCard

  alias BlackboexWeb.LastVisited

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    user = scope.user

    cond do
      socket.assigns.live_action == :dashboard ->
        render_dashboard(socket, org)

      org && user ->
        case LastVisited.resolve_project_for_org(user, org) do
          {:ok, project} ->
            {:ok, push_navigate(socket, to: "/orgs/#{org.slug}/projects/#{project.slug}")}

          _ ->
            render_dashboard(socket, org)
        end

      true ->
        render_dashboard(socket, org)
    end
  end

  defp render_dashboard(socket, org) do
    {usage, total_apis, total_projects} =
      if org do
        usage = Blackboex.Billing.get_org_usage_summary(org.id)
        total_apis = Blackboex.Apis.count_apis_for_org(org.id)
        total_projects = Blackboex.Projects.count_projects_for_org(org.id)
        {usage, total_apis, total_projects}
      else
        {%{
           api_invocations: 0,
           llm_generations: 0,
           tokens_input: 0,
           tokens_output: 0,
           llm_cost_cents: 0
         }, 0, 0}
      end

    socket =
      socket
      |> assign(:page_title, "#{(org && org.name) || "Org"} Dashboard")
      |> assign(:usage, usage)
      |> assign(:total_apis, total_apis)
      |> assign(:total_projects, total_projects)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-building-office" class="size-5 text-accent-blue" />
          {@current_scope.organization && @current_scope.organization.name}
        </span>
        <:subtitle>Organization overview</:subtitle>
      </.header>

      <.stat_grid cols="4">
        <.stat_card
          label="Total Projects"
          value={@total_projects}
          icon="hero-folder"
          icon_class="text-accent-blue"
        />
        <.stat_card
          label="Total APIs"
          value={@total_apis}
          icon="hero-bolt"
          icon_class="text-accent-amber"
        />
        <.stat_card
          label="API Invocations (30d)"
          value={@usage.api_invocations}
          icon="hero-arrow-path"
          icon_class="text-accent-emerald"
        />
        <.stat_card
          label="LLM Calls (30d)"
          value={@usage.llm_generations}
          icon="hero-cpu-chip"
          icon_class="text-accent-violet"
        />
      </.stat_grid>
    </.page>
    """
  end
end
