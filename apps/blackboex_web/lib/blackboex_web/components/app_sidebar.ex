defmodule BlackboexWeb.Components.AppSidebar do
  @moduledoc """
  Vertical sidebar navigation component for the app layout.

  Collapse/expand is CSS-driven via the `sidebar-collapsed` class so there is
  no server round-trip. In app layout the sidebar pushes content; in editor
  layout it expands as an absolute overlay. State is persisted to
  localStorage via the SidebarCollapse JS hook.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.OrgProjectSwitcher

  alias BlackboexWeb.Components.SidebarTreeComponent

  @doc """
  Renders the sidebar navigation.

  ## Attrs

    * `current_scope` — the current scope with organization and project
    * `current_path` — the current URL path for active state detection
    * `collapsed` — render collapsed initially (editor mode); default false
    * `id` — sidebar element ID
  """
  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: nil
  attr :collapsed, :boolean, default: false
  attr :id, :string, default: "app-sidebar"

  def sidebar(assigns) do
    assigns = assign(assigns, :effective_collapsed, false)

    ~H"""
    <aside
      id={@id}
      phx-hook={if not @collapsed, do: "SidebarCollapse"}
      class={[
        "group/sidebar relative flex flex-col border-r bg-card text-card-foreground shrink-0 transition-all duration-200",
        if(@effective_collapsed, do: "w-14 sidebar-collapsed", else: "w-60")
      ]}
    >
      <%!-- Editor-mode hover-to-expand button (absolute, outside header) --%>
      <button
        :if={@collapsed}
        class="absolute top-2 -right-3 z-50 hidden group-hover/sidebar:flex h-6 w-6 items-center justify-center rounded-full border bg-card shadow-sm text-muted-foreground hover:text-foreground"
        phx-click={toggle_sidebar_expand(@id)}
      >
        <span id={"#{@id}-expand-icon"}>
          <.icon name="hero-chevron-right-micro" class="size-3" />
        </span>
      </button>

      <%!-- Expanded header: logo + title + collapse button --%>
      <div class="flex items-center gap-2.5 px-4 py-3 border-b group-[.sidebar-collapsed]/sidebar:hidden">
        <.logo_icon class="h-6 w-6 shrink-0" />
        <span class="flex-1 text-sm font-bold tracking-tight truncate">BlackBoex</span>
        <button
          :if={not @collapsed}
          class="flex h-6 w-6 shrink-0 items-center justify-center rounded-md text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
          phx-click={toggle_sidebar(@id)}
          title="Collapse sidebar"
        >
          <.icon name="hero-chevron-left-micro" class="size-3" />
        </button>
      </div>

      <%!-- Collapsed header: centered logo + expand button --%>
      <div class="hidden group-[.sidebar-collapsed]/sidebar:flex flex-col items-center py-3 gap-1 border-b">
        <.logo_icon class="h-6 w-6" />
        <button
          :if={not @collapsed}
          class="flex h-6 w-6 items-center justify-center rounded-md text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
          phx-click={toggle_sidebar(@id)}
          title="Expand sidebar"
        >
          <.icon name="hero-chevron-right-micro" class="size-3" />
        </button>
      </div>

      <%!-- Org/Project switcher --%>
      <div :if={scoped?(@current_scope)} class="border-b">
        <div class="px-3 py-2.5 group-[.sidebar-collapsed]/sidebar:hidden">
          <.org_project_switcher current_scope={@current_scope} />
        </div>
        <div class="hidden group-[.sidebar-collapsed]/sidebar:flex justify-center py-2">
          <div class="flex h-7 w-7 items-center justify-center rounded-md bg-primary/10 text-primary text-[10px] font-bold">
            {String.first(@current_scope.organization.name) |> String.upcase()}
          </div>
        </div>
      </div>

      <%!-- Navigation --%>
      <nav class="flex-1 overflow-y-auto py-2">
        <.live_component
          module={SidebarTreeComponent}
          id={"#{@id}-tree"}
          current_scope={@current_scope}
          current_path={@current_path}
          collapsed={false}
        />
      </nav>

      <%!-- User section --%>
      <div class="border-t py-2">
        <%= if @current_scope && @current_scope.user do %>
          <div class="mt-2 px-2 flex items-center gap-2 group-[.sidebar-collapsed]/sidebar:flex-col group-[.sidebar-collapsed]/sidebar:items-center">
            <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent text-xs font-medium">
              {String.first(@current_scope.user.email) |> String.upcase()}
            </div>
            <span class="min-w-0 flex-1 truncate text-xs text-muted-foreground group-[.sidebar-collapsed]/sidebar:hidden">
              {@current_scope.user.email}
            </span>
          </div>
          <div class="mt-1 px-2 group-[.sidebar-collapsed]/sidebar:flex group-[.sidebar-collapsed]/sidebar:justify-center">
            <.link
              href="/users/log-out"
              method="delete"
              class="flex items-center gap-2 rounded-md px-3 py-1.5 text-sm text-muted-foreground hover:bg-accent hover:text-accent-foreground group-[.sidebar-collapsed]/sidebar:px-2 group-[.sidebar-collapsed]/sidebar:justify-center"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
              <span class="group-[.sidebar-collapsed]/sidebar:hidden">Log out</span>
            </.link>
          </div>
        <% end %>
      </div>
    </aside>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp scoped?(nil), do: false
  defp scoped?(%{organization: nil}), do: false
  defp scoped?(%{organization: _org}), do: true

  # Push toggle for app layout — sidebar shrinks and content expands naturally.
  defp toggle_sidebar(sidebar_id) do
    JS.toggle_class("sidebar-collapsed w-14", to: "##{sidebar_id}")
    |> JS.toggle_class("w-60", to: "##{sidebar_id}")
    |> JS.dispatch("sidebar:toggled", to: "##{sidebar_id}")
  end

  # Overlay toggle for editor layout — expands sidebar as an absolute drawer
  # so the editor canvas does not reflow.
  defp toggle_sidebar_expand(sidebar_id) do
    JS.toggle_class("sidebar-collapsed w-14", to: "##{sidebar_id}")
    |> JS.toggle_class("w-60 absolute z-50 h-full shadow-xl", to: "##{sidebar_id}")
    |> JS.toggle_class("rotate-180", to: "##{sidebar_id}-expand-icon")
  end
end
