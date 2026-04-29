defmodule BlackboexWeb.Components.OrgProjectSwitcher do
  @moduledoc """
  Shows the current organization and project context in the sidebar.
  Org and project names are always visible. Small chevron buttons open
  dropdown menus for switching.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.DropdownMenu

  alias Blackboex.Organizations
  alias Blackboex.Projects

  attr :current_scope, :map, required: true
  attr :orgs, :list, default: nil
  attr :projects, :list, default: nil
  attr :show_project, :boolean, default: true

  def org_project_switcher(assigns) do
    user = assigns.current_scope && assigns.current_scope.user
    org = assigns.current_scope && assigns.current_scope.organization
    project = assigns.current_scope && assigns.current_scope.project

    orgs = assigns.orgs || if(user, do: Organizations.list_user_organizations(user), else: [])

    projects =
      assigns.projects ||
        if(org, do: Projects.list_user_projects(org.id, user && user.id), else: [])

    assigns =
      assigns
      |> assign(:orgs, orgs)
      |> assign(:projects, projects)
      |> assign(:current_org, org)
      |> assign(:current_project, project)

    ~H"""
    <div class="space-y-1.5">
      <%!-- Organization row --%>
      <div class="flex items-center gap-2">
        <div class="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-primary/10 text-primary text-[10px] font-bold">
          {org_initials(@current_org)}
        </div>
        <div class="flex-1 min-w-0 flex items-center gap-1">
          <.dropdown_menu>
            <.dropdown_menu_trigger>
              <button class="flex min-w-0 items-center gap-1 text-left group">
                <span class="text-xs font-medium text-muted-foreground truncate group-hover:text-foreground transition-colors">
                  {org_name(@current_org)}
                </span>
                <.icon
                  name="hero-chevron-down-micro"
                  class="size-3 text-muted-foreground/50 shrink-0 group-hover:text-foreground transition-colors"
                />
              </button>
            </.dropdown_menu_trigger>
            <.dropdown_menu_content class="w-56 ml-0 left-0 top-full mt-1 rounded-lg border bg-popover p-1 shadow-lg">
              <div class="px-2 py-1.5 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                Switch organization
              </div>
              <.link
                :for={org <- @orgs}
                navigate={"/orgs/#{org.slug}"}
                class={[
                  "flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-sm hover:bg-accent cursor-pointer",
                  if(org.id == (@current_org && @current_org.id), do: "bg-accent/50", else: "")
                ]}
              >
                <div class="flex h-5 w-5 shrink-0 items-center justify-center rounded bg-muted text-[9px] font-medium">
                  {org_initials(org)}
                </div>
                <span class="truncate">{org.name}</span>
                <.icon
                  :if={org.id == (@current_org && @current_org.id)}
                  name="hero-check-micro"
                  class="ml-auto size-3.5 text-primary"
                />
              </.link>
            </.dropdown_menu_content>
          </.dropdown_menu>
          <div :if={@current_org} class="ml-auto flex items-center gap-0.5">
            <.link
              navigate={"/orgs/#{@current_org.slug}/settings"}
              class="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-accent"
              title="Org settings"
              aria-label="Org settings"
            >
              <.icon name="hero-cog-6-tooth-micro" class="size-3.5" />
            </.link>
          </div>
        </div>
      </div>

      <%!-- Project row --%>
      <div :if={@show_project} class="flex items-center gap-2">
        <div class="flex h-6 w-6 shrink-0 items-center justify-center">
          <.icon name="hero-folder-micro" class="size-4 text-muted-foreground/60" />
        </div>
        <div class="flex-1 min-w-0 flex items-center gap-1">
          <.dropdown_menu>
            <.dropdown_menu_trigger>
              <button class="flex min-w-0 items-center gap-1 text-left group">
                <span class="text-sm font-semibold truncate group-hover:text-primary transition-colors">
                  {project_name(@current_project)}
                </span>
                <.icon
                  name="hero-chevron-down-micro"
                  class="size-3 text-muted-foreground/50 shrink-0 group-hover:text-foreground transition-colors"
                />
              </button>
            </.dropdown_menu_trigger>
            <.dropdown_menu_content class="w-56 ml-0 left-0 top-full mt-1 rounded-lg border bg-popover p-1 shadow-lg">
              <div class="px-2 py-1.5 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                Switch project
              </div>
              <.link
                :for={project <- @projects}
                navigate={"/orgs/#{@current_org && @current_org.slug}/projects/#{project.slug}"}
                class={[
                  "flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-sm hover:bg-accent cursor-pointer",
                  if(project.id == (@current_project && @current_project.id),
                    do: "bg-accent/50",
                    else: ""
                  )
                ]}
              >
                <span class="truncate">{project.name}</span>
                <.icon
                  :if={project.id == (@current_project && @current_project.id)}
                  name="hero-check-micro"
                  class="ml-auto size-3.5 text-primary"
                />
              </.link>

              <div class="my-1 h-px bg-border" />

              <.link
                navigate={"/orgs/#{@current_org && @current_org.slug}/projects/new"}
                class="flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-sm text-muted-foreground hover:bg-accent cursor-pointer"
              >
                <.icon name="hero-plus-micro" class="size-3.5" />
                <span>New project</span>
              </.link>
            </.dropdown_menu_content>
          </.dropdown_menu>
          <div :if={@current_org && @current_project} class="ml-auto flex items-center gap-0.5">
            <.link
              navigate={"/orgs/#{@current_org.slug}/projects/#{@current_project.slug}/settings"}
              class="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-accent"
              title="Project settings"
              aria-label="Project settings"
            >
              <.icon name="hero-cog-6-tooth-micro" class="size-3.5" />
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp org_initials(nil), do: "?"

  defp org_initials(%{name: name}) when is_binary(name) do
    name
    |> String.split(~r/\s+/)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp org_name(nil), do: "Select org"
  defp org_name(%{name: name}), do: name

  defp project_name(nil), do: "Select project"
  defp project_name(%{name: name}), do: name
end
