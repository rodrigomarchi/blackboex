defmodule BlackboexWeb.ProjectLive.Index do
  @moduledoc """
  Lists projects for the current organization.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge

  alias Blackboex.Projects

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    projects = if org, do: Projects.list_projects(org.id), else: []

    {:ok,
     socket
     |> assign(:projects, projects)
     |> assign(:page_title, "Projects")
     |> assign(:org, org)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-folder" class="size-5 text-accent-blue" /> Projects
        </span>
        <:subtitle>Manage projects in this organization</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/orgs/#{@org.slug}/projects/new"}>
            <.icon name="hero-plus" class="mr-2 size-4 text-accent-emerald" /> New Project
          </.button>
        </:actions>
      </.header>

      <%= if @projects == [] do %>
        <.empty_state
          icon="hero-folder"
          title="No projects yet"
          description="Create a project to organize your APIs and flows."
        >
          <:actions>
            <.button variant="primary" navigate={~p"/orgs/#{@org.slug}/projects/new"}>
              Create Project
            </.button>
          </:actions>
        </.empty_state>
      <% else %>
        <.table
          id="projects"
          rows={@projects}
          row_click={
            fn project -> JS.navigate(~p"/orgs/#{@org.slug}/projects/#{project.slug}/settings") end
          }
        >
          <:col :let={project} label="Name">
            <span class="font-medium">{project.name}</span>
          </:col>
          <:col :let={project} label="Slug">
            <.badge variant="outline">{project.slug}</.badge>
          </:col>
          <:action :let={project}>
            <.link
              navigate={~p"/orgs/#{@org.slug}/projects/#{project.slug}/settings"}
              class="link-primary"
            >
              <.icon name="hero-arrow-right-mini" class="size-4" />
            </.link>
          </:action>
        </.table>
      <% end %>
    </.page>
    """
  end
end
