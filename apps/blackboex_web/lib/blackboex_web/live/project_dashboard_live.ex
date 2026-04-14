defmodule BlackboexWeb.ProjectDashboardLive do
  @moduledoc """
  Project-level dashboard.

  Shows stats and activity for a single project.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Shared.StatCard

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.current_scope.project

    {usage, total_apis} =
      if project do
        usage = Blackboex.Billing.get_project_usage_summary(project.id)
        total_apis = Blackboex.Apis.count_apis_for_project(project.id)
        {usage, total_apis}
      else
        {%{
           api_invocations: 0,
           llm_generations: 0,
           tokens_input: 0,
           tokens_output: 0,
           llm_cost_cents: 0
         }, 0}
      end

    socket =
      socket
      |> assign(:page_title, "#{(project && project.name) || "Project"} Dashboard")
      |> assign(:usage, usage)
      |> assign(:total_apis, total_apis)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-folder" class="size-5 text-accent-blue" />
          {@current_scope.project && @current_scope.project.name}
        </span>
        <:subtitle>Project overview</:subtitle>
      </.header>

      <.stat_grid cols="3">
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
