defmodule BlackboexWeb.Components.AppSidebar do
  @moduledoc """
  Vertical sidebar navigation component for the app layout.

  Renders grouped navigation items: WORK (APIs, Flows, Pages, Playgrounds),
  CONFIG (API Keys), and a bottom section (Settings, User menu).

  Supports collapsed mode (icon strip) for editor layouts.
  """

  use BlackboexWeb, :html

  import SaladUI.Separator
  import SaladUI.Tooltip
  import BlackboexWeb.Components.OrgProjectSwitcher

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
    ~H"""
    <aside
      id={@id}
      class={[
        "relative flex flex-col border-r bg-card text-card-foreground shrink-0 transition-all duration-200",
        if(@collapsed, do: "w-14 group/sidebar", else: "w-60")
      ]}
    >
      <%!-- Expand/collapse toggle for editor sidebar --%>
      <button
        :if={@collapsed}
        class="absolute top-2 -right-3 z-50 hidden group-hover/sidebar:flex h-6 w-6 items-center justify-center rounded-full border bg-card shadow-sm text-muted-foreground hover:text-foreground"
        phx-click={toggle_sidebar_expand(@id)}
      >
        <span id={"#{@id}-expand-icon"}>
          <.icon name="hero-chevron-right-micro" class="size-3" />
        </span>
      </button>
      <%!-- Header: Logo + Org/Project context --%>
      <div class="border-b">
        <%!-- Logo row --%>
        <div class={[
          "flex items-center border-b border-border/50",
          if(@collapsed, do: "justify-center px-2 py-3", else: "gap-2.5 px-4 py-3")
        ]}>
          <.logo_icon class="h-6 w-6 shrink-0" />
          <span :if={!@collapsed} class="text-sm font-bold tracking-tight">BlackBoex</span>
        </div>

        <%!-- Org/Project context (always visible when scoped) --%>
        <div :if={scoped?(@current_scope) and not @collapsed} class="px-3 py-2.5">
          <.org_project_switcher current_scope={@current_scope} />
        </div>
        <div :if={scoped?(@current_scope) and @collapsed} class="flex justify-center py-2">
          <div class="flex h-7 w-7 items-center justify-center rounded-md bg-primary/10 text-primary text-[10px] font-bold">
            {String.first(@current_scope.organization.name) |> String.upcase()}
          </div>
        </div>
      </div>

      <%!-- Navigation groups --%>
      <nav class="flex-1 overflow-y-auto py-2">
        <%!-- WORK group --%>
        <.sidebar_group label="WORK" collapsed={@collapsed}>
          <.sidebar_nav_item
            icon="hero-bolt"
            label="APIs"
            href={project_path(@current_scope, "/apis")}
            active={active?(@current_path, "/apis")}
            collapsed={@collapsed}
            accent="text-accent-amber"
          />
          <.sidebar_nav_item
            icon="hero-arrow-path"
            label="Flows"
            href={project_path(@current_scope, "/flows")}
            active={active?(@current_path, "/flows")}
            collapsed={@collapsed}
            accent="text-accent-violet"
          />
          <.sidebar_nav_item
            icon="hero-document-text"
            label="Pages"
            href={project_path(@current_scope, "/pages")}
            active={active?(@current_path, "/pages")}
            collapsed={@collapsed}
            accent="text-accent-sky"
          />
          <.sidebar_nav_item
            icon="hero-code-bracket"
            label="Playgrounds"
            href={project_path(@current_scope, "/playgrounds")}
            active={active?(@current_path, "/playgrounds")}
            collapsed={@collapsed}
            accent="text-accent-emerald"
          />
        </.sidebar_group>

        <.separator class="my-2" />

        <%!-- CONFIG group --%>
        <.sidebar_group label="CONFIG" collapsed={@collapsed}>
          <.sidebar_nav_item
            icon="hero-key"
            label="API Keys"
            href={project_path(@current_scope, "/api-keys")}
            active={active?(@current_path, "/api-keys")}
            collapsed={@collapsed}
            accent="text-accent-amber"
          />
        </.sidebar_group>
      </nav>

      <%!-- Bottom section --%>
      <div class="border-t py-2">
        <.sidebar_nav_item
          icon="hero-cog-6-tooth"
          label="Project Settings"
          href={project_path(@current_scope, "/settings")}
          active={
            active?(@current_path, "/settings") and
              not String.contains?(@current_path || "", "/orgs/")
          }
          collapsed={@collapsed}
          accent="text-slate-400"
        />
        <.sidebar_nav_item
          :if={scoped?(@current_scope)}
          icon="hero-building-office-2"
          label="Org Settings"
          href={org_path(@current_scope, "/settings")}
          active={org_settings_active?(@current_path, @current_scope)}
          collapsed={@collapsed}
          accent="text-slate-400"
        />

        <.separator class="my-2" />

        <%!-- Theme toggle --%>
        <div class={["px-2", if(@collapsed, do: "flex justify-center")]}>
          <.theme_toggle_compact collapsed={@collapsed} />
        </div>

        <%!-- User info + logout --%>
        <%= if @current_scope && @current_scope.user do %>
          <div class={[
            "mt-2 px-2",
            if(@collapsed, do: "flex flex-col items-center gap-1", else: "flex items-center gap-2")
          ]}>
            <div class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent text-xs font-medium">
              {String.first(@current_scope.user.email) |> String.upcase()}
            </div>
            <span :if={!@collapsed} class="min-w-0 flex-1 truncate text-xs text-muted-foreground">
              {@current_scope.user.email}
            </span>
          </div>
          <div class={["mt-1 px-2", if(@collapsed, do: "flex justify-center")]}>
            <.link
              href="/users/log-out"
              method="delete"
              class={[
                "flex items-center gap-2 rounded-md text-sm text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                if(@collapsed, do: "justify-center p-2", else: "px-3 py-1.5")
              ]}
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
              <span :if={!@collapsed}>Log out</span>
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

  attr :collapsed, :boolean, default: false

  defp theme_toggle_compact(assigns) do
    ~H"""
    <div class={[
      "relative flex flex-row items-center border border-border bg-muted rounded-full",
      if(@collapsed, do: "w-10", else: "w-auto")
    ]}>
      <.button
        type="button"
        variant="ghost"
        size="icon"
        class="flex h-auto w-1/3 cursor-pointer rounded-none p-1.5"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-3 opacity-75 hover:opacity-100" />
      </.button>
      <.button
        :if={!@collapsed}
        type="button"
        variant="ghost"
        size="icon"
        class="flex h-auto w-1/3 cursor-pointer rounded-none p-1.5"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-3 opacity-75 hover:opacity-100" />
      </.button>
      <.button
        :if={!@collapsed}
        type="button"
        variant="ghost"
        size="icon"
        class="flex h-auto w-1/3 cursor-pointer rounded-none p-1.5"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-3 opacity-75 hover:opacity-100" />
      </.button>
    </div>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────

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

  defp org_settings_active?(nil, _scope), do: false

  defp org_settings_active?(current_path, scope) do
    scoped?(scope) and
      String.starts_with?(current_path, org_path(scope, "/settings"))
  end

  defp toggle_sidebar_expand(sidebar_id) do
    # Toggle between collapsed (w-14) and expanded overlay (w-60 absolute shadow)
    JS.toggle_class("w-14", to: "##{sidebar_id}")
    |> JS.toggle_class("w-60 absolute z-50 h-full shadow-xl", to: "##{sidebar_id}")
    |> JS.toggle_class("rotate-180",
      to: "##{sidebar_id}-expand-icon"
    )
  end
end
