defmodule BlackboexWeb.Components.AppSidebar do
  @moduledoc """
  Vertical sidebar navigation component for the app layout.

  Renders grouped navigation items: WORK (APIs, Flows, Pages, Playgrounds)
  and a bottom section (Theme toggle, User menu). Project-level config
  (API Keys, Env Vars, LLM Integrations) is exposed via the project
  settings tabs inside each project page — not duplicated in the sidebar.

  Supports collapsed mode (icon strip) for editor layouts.
  """

  use BlackboexWeb, :html

  import SaladUI.Tooltip
  import BlackboexWeb.Components.OrgProjectSwitcher

  alias BlackboexWeb.Components.SidebarTreeComponent

  @doc """
  Renders the sidebar navigation.

  ## Attrs

    * `current_scope` — the current scope with organization and project
    * `current_path` — the current URL path for active state detection
    * `collapsed` — whether to render the collapsed icon strip (default: false)
  """
  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: nil
  attr :collapsed, :boolean, default: false
  attr :id, :string, default: "app-sidebar"

  def sidebar(assigns) do
    tree_active = tree_v2_enabled?(assigns[:current_scope])
    effective_collapsed = assigns[:collapsed] and not tree_active

    assigns =
      assigns
      |> assign(:tree_active, tree_active)
      |> assign(:effective_collapsed, effective_collapsed)

    ~H"""
    <aside
      id={@id}
      class={[
        "relative flex flex-col border-r bg-card text-card-foreground shrink-0 transition-all duration-200",
        if(@effective_collapsed, do: "w-14 group/sidebar", else: "w-60")
      ]}
    >
      <button
        :if={@effective_collapsed}
        class="absolute top-2 -right-3 z-50 hidden group-hover/sidebar:flex h-6 w-6 items-center justify-center rounded-full border bg-card shadow-sm text-muted-foreground hover:text-foreground"
        phx-click={toggle_sidebar_expand(@id)}
      >
        <span id={"#{@id}-expand-icon"}>
          <.icon name="hero-chevron-right-micro" class="size-3" />
        </span>
      </button>
      <div class="border-b">
        <div class={[
          "flex items-center border-b border-border/50",
          if(@effective_collapsed, do: "justify-center px-2 py-3", else: "gap-2.5 px-4 py-3")
        ]}>
          <.logo_icon class="h-6 w-6 shrink-0" />
          <span :if={!@effective_collapsed} class="text-sm font-bold tracking-tight">
            BlackBoex
          </span>
        </div>

        <div :if={scoped?(@current_scope) and not @effective_collapsed} class="px-3 py-2.5">
          <.org_project_switcher
            current_scope={@current_scope}
            show_project={not @tree_active}
          />
        </div>
        <div :if={scoped?(@current_scope) and @effective_collapsed} class="flex justify-center py-2">
          <div class="flex h-7 w-7 items-center justify-center rounded-md bg-primary/10 text-primary text-[10px] font-bold">
            {String.first(@current_scope.organization.name) |> String.upcase()}
          </div>
        </div>
      </div>

      <nav class="flex-1 overflow-y-auto py-2">
        <%= cond do %>
          <% @tree_active -> %>
            <.live_component
              module={SidebarTreeComponent}
              id={"#{@id}-tree"}
              current_scope={@current_scope}
              current_path={@current_path}
              collapsed={false}
            />
          <% @effective_collapsed -> %>
            <.sidebar_group label="WORK" collapsed={@effective_collapsed}>
              <.sidebar_nav_item
                icon="hero-bolt"
                label="APIs"
                href={project_path(@current_scope, "/apis")}
                active={active?(@current_path, "/apis")}
                collapsed={@effective_collapsed}
                accent="text-accent-amber"
              />
              <.sidebar_nav_item
                icon="hero-arrow-path"
                label="Flows"
                href={project_path(@current_scope, "/flows")}
                active={active?(@current_path, "/flows")}
                collapsed={@effective_collapsed}
                accent="text-accent-violet"
              />
              <.sidebar_nav_item
                icon="hero-document-text"
                label="Pages"
                href={project_path(@current_scope, "/pages")}
                active={active?(@current_path, "/pages")}
                collapsed={@effective_collapsed}
                accent="text-accent-sky"
              />
              <.sidebar_nav_item
                icon="hero-code-bracket"
                label="Playgrounds"
                href={project_path(@current_scope, "/playgrounds")}
                active={active?(@current_path, "/playgrounds")}
                collapsed={@effective_collapsed}
                accent="text-accent-emerald"
              />
            </.sidebar_group>
          <% true -> %>
            <.sidebar_group label="WORK" collapsed={@effective_collapsed}>
              <.sidebar_nav_item
                icon="hero-bolt-slash"
                label="APIs"
                href={project_path(@current_scope, "/apis")}
                active={active?(@current_path, "/apis")}
                collapsed={@effective_collapsed}
              />
              <.sidebar_nav_item
                icon="hero-arrows-right-left"
                label="Flows"
                href={project_path(@current_scope, "/flows")}
                active={active?(@current_path, "/flows")}
                collapsed={@effective_collapsed}
              />
              <.sidebar_nav_item
                icon="hero-document-text"
                label="Pages"
                href={project_path(@current_scope, "/pages")}
                active={active?(@current_path, "/pages")}
                collapsed={@effective_collapsed}
              />
              <.sidebar_nav_item
                icon="hero-code-bracket"
                label="Playgrounds"
                href={project_path(@current_scope, "/playgrounds")}
                active={active?(@current_path, "/playgrounds")}
                collapsed={@effective_collapsed}
              />
            </.sidebar_group>
        <% end %>
      </nav>

      <div class="border-t py-2">
        <%= if @current_scope && @current_scope.user do %>
          <div class={[
            "mt-2 px-2",
            if(@effective_collapsed,
              do: "flex flex-col items-center gap-1",
              else: "flex items-center gap-2"
            )
          ]}>
            <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent text-xs font-medium">
              {String.first(@current_scope.user.email) |> String.upcase()}
            </div>
            <span
              :if={!@effective_collapsed}
              class="min-w-0 flex-1 truncate text-xs text-muted-foreground"
            >
              {@current_scope.user.email}
            </span>
          </div>
          <div class={["mt-1 px-2", if(@effective_collapsed, do: "flex justify-center")]}>
            <.link
              href="/users/log-out"
              method="delete"
              class={[
                "flex items-center gap-2 rounded-md text-sm text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                if(@effective_collapsed, do: "justify-center p-2", else: "px-3 py-1.5")
              ]}
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
              <span :if={!@effective_collapsed}>Log out</span>
            </.link>
          </div>
        <% end %>
      </div>
    </aside>
    """
  end

  # ── Private components ──────────────────────────────────────

  attr :label, :string, required: true
  attr :collapsed, :boolean, default: false
  slot :inner_block, required: true

  defp sidebar_group(assigns) do
    ~H"""
    <div class="px-2">
      <span
        :if={!@collapsed}
        class="mb-1 block px-3 pt-2 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground"
      >
        {@label}
      </span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :active, :boolean, default: false
  attr :collapsed, :boolean, default: false
  attr :accent, :string, default: "text-muted-foreground"

  defp sidebar_nav_item(assigns) do
    ~H"""
    <%= if @collapsed do %>
      <.tooltip>
        <.tooltip_trigger>
          <.link
            navigate={@href}
            class={[
              "flex items-center justify-center rounded-md p-2 transition-colors",
              if(@active,
                do: "bg-accent text-accent-foreground",
                else: "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
              )
            ]}
          >
            <.icon name={@icon} class={["size-4", @accent]} />
          </.link>
        </.tooltip_trigger>
        <.tooltip_content side="right">
          {@label}
        </.tooltip_content>
      </.tooltip>
    <% else %>
      <.link
        navigate={@href}
        class={[
          "flex items-center gap-2 rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
          if(@active,
            do: "bg-accent text-accent-foreground",
            else: "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
          )
        ]}
      >
        <.icon name={@icon} class={["size-4", @accent]} />
        {@label}
      </.link>
    <% end %>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp tree_v2_enabled?(nil), do: false
  defp tree_v2_enabled?(%{user: nil}), do: false
  defp tree_v2_enabled?(%{user: user}), do: FunWithFlags.enabled?(:sidebar_tree_v2, for: user)

  defp scoped?(nil), do: false
  defp scoped?(%{organization: nil}), do: false
  defp scoped?(%{organization: _org}), do: true

  defp active?(nil, _prefix), do: false

  defp active?(current_path, prefix) when is_binary(current_path) do
    # Match the path segment after the project slug portion
    # e.g., /orgs/acme/projects/my-proj/apis/some-api matches "/apis"
    # Works for nested routes like /apis/:slug/edit, /apis/new, etc.
    suffix = String.trim_leading(prefix, "/")
    String.contains?(current_path, "/#{suffix}")
  end

  defp toggle_sidebar_expand(sidebar_id) do
    JS.toggle_class("w-14", to: "##{sidebar_id}")
    |> JS.toggle_class("w-60 absolute z-50 h-full shadow-xl", to: "##{sidebar_id}")
    |> JS.toggle_class("rotate-180",
      to: "##{sidebar_id}-expand-icon"
    )
  end
end
