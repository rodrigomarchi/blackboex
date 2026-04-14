defmodule BlackboexWeb.Components.Shared.ProjectSwitcher do
  @moduledoc """
  Project switcher dropdown component.
  Shows current project name and org, with a dropdown to switch projects.
  """
  use BlackboexWeb.Component
  import BlackboexWeb.Components.Icon

  attr :org, :map, required: true
  attr :project, :map, default: nil
  attr :projects, :list, default: []

  def project_switcher(assigns) do
    ~H"""
    <div class="flex flex-col gap-1" data-role="project-switcher">
      <p class="text-xs text-muted-foreground font-medium uppercase tracking-wider px-2">
        {@org.name}
      </p>
      <div class="flex items-center gap-2 px-2 py-1.5 rounded-md bg-muted/50">
        <.icon name="hero-folder" class="size-4 text-accent-blue shrink-0" />
        <span class="text-sm font-medium truncate">
          {(@project && @project.name) || "No Project"}
        </span>
      </div>
      <nav :if={@projects != []} class="flex flex-col gap-0.5 mt-1">
        <.link
          :for={p <- @projects}
          navigate={"/orgs/#{@org.slug}/projects/#{p.slug}"}
          class={[
            "flex items-center gap-2 px-2 py-1.5 rounded-md text-sm hover:bg-muted transition-colors",
            if(@project && @project.id == p.id, do: "bg-muted font-medium", else: "")
          ]}
        >
          <.icon name="hero-folder-open" class="size-3.5 shrink-0" />
          {p.name}
        </.link>
        <.link
          navigate={"/orgs/#{@org.slug}/projects/new"}
          class="flex items-center gap-2 px-2 py-1.5 rounded-md text-sm text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
        >
          <.icon name="hero-plus-circle" class="size-3.5 shrink-0" /> New project
        </.link>
      </nav>
    </div>
    """
  end
end
