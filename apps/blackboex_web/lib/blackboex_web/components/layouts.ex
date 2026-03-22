defmodule BlackboexWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BlackboexWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  def app(assigns) do
    ~H"""
    <div class="flex h-screen flex-col">
      <header class="flex h-14 shrink-0 items-center border-b bg-card px-4 md:px-6">
        <%!-- Logo --%>
        <.logo_full class="h-6" />

        <%!-- Desktop nav --%>
        <nav class="ml-8 hidden items-center gap-1 md:flex">
          <.nav_link navigate={~p"/dashboard"} icon="hero-home">Dashboard</.nav_link>
          <.nav_link navigate={~p"/apis"} icon="hero-bolt">APIs</.nav_link>
          <.nav_link navigate={~p"/api-keys"} icon="hero-key">API Keys</.nav_link>
          <.nav_link navigate={~p"/billing"} icon="hero-credit-card">Billing</.nav_link>
        </nav>

        <div class="flex-1" />

        <%!-- Right side: theme toggle + user menu --%>
        <div class="flex items-center gap-3">
          <.theme_toggle />
          <%= if @current_scope && @current_scope.user do %>
            <span class="hidden text-sm text-muted-foreground md:inline">
              {@current_scope.user.email}
            </span>
            <.link
              navigate={~p"/settings"}
              class="hidden text-sm font-medium text-muted-foreground hover:text-foreground md:inline"
            >
              <.icon name="hero-cog-6-tooth" class="size-4" />
            </.link>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="hidden text-sm font-medium hover:underline md:inline"
            >
              Log out
            </.link>
          <% end %>

          <%!-- Mobile hamburger --%>
          <button
            class="inline-flex items-center justify-center rounded-md p-2 hover:bg-accent md:hidden"
            phx-click={toggle_mobile_menu()}
          >
            <span id="mobile-menu-open"><.icon name="hero-bars-3" class="size-5" /></span>
            <span id="mobile-menu-close" class="hidden">
              <.icon name="hero-x-mark" class="size-5" />
            </span>
          </button>
        </div>
      </header>

      <%!-- Mobile menu (hidden by default) --%>
      <div id="mobile-menu" class="hidden border-b bg-card px-4 py-3 md:hidden">
        <nav class="flex flex-col gap-1">
          <.nav_link navigate={~p"/dashboard"} icon="hero-home">Dashboard</.nav_link>
          <.nav_link navigate={~p"/apis"} icon="hero-bolt">APIs</.nav_link>
          <.nav_link navigate={~p"/api-keys"} icon="hero-key">API Keys</.nav_link>
          <.nav_link navigate={~p"/billing"} icon="hero-credit-card">Billing</.nav_link>
          <.nav_link navigate={~p"/settings"} icon="hero-cog-6-tooth">Settings</.nav_link>
        </nav>
        <%= if @current_scope && @current_scope.user do %>
          <div class="mt-3 border-t pt-3">
            <span class="text-sm text-muted-foreground">{@current_scope.user.email}</span>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="mt-2 block text-sm font-medium hover:underline"
            >
              Log out
            </.link>
          </div>
        <% end %>
      </div>

      <main class="flex-1 overflow-y-auto p-4 md:p-6">
        <div class="mx-auto max-w-6xl">
          {@inner_content}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Auth layout for login/register pages.
  Centered card without app navigation.
  """
  attr :flash, :map, required: true

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  def auth(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col items-center justify-center bg-background px-4">
      <div class="mb-8">
        <.logo_full class="h-8" />
      </div>

      <div class="w-full max-w-md rounded-lg border bg-card p-8 shadow-sm">
        {@inner_content}
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Editor layout for the API code editor page.
  Full-width, full-height, minimal chrome — the editor page manages its own toolbar.
  """
  attr :flash, :map, required: true

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  def editor(assigns) do
    ~H"""
    <div class="h-screen overflow-hidden bg-background text-foreground">
      {@inner_content}
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Bare layout for the admin live_session.
  Backpex LiveResources apply their own layout via the `<.layout>` component,
  so this just passes through the content with flash messages.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil

  def admin_bare(assigns) do
    ~H"""
    {@inner_content}
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Admin layout for Backpex admin panel.
  Uses Backpex's app_shell component with sidebar navigation.
  Called by Backpex LiveResources (content in @inner_content) and
  directly by the dashboard LiveView (content in @inner_block).
  """
  slot :inner_block
  slot :inner_content

  def admin(assigns) do
    ~H"""
    <Backpex.HTML.Layout.app_shell>
      <:topbar>
        <a href="/" class="text-lg font-semibold">BlackBoex Admin</a>
      </:topbar>
      <:sidebar>
        <li>
          <.link href={~p"/admin"} class="flex items-center gap-2">
            <.icon name="hero-chart-bar" class="size-4" /> Dashboard
          </.link>
        </li>
        <li class="menu-title mt-3">Core</li>
        <li>
          <.link href={~p"/admin/users"} class="flex items-center gap-2">
            <.icon name="hero-users" class="size-4" /> Users
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/organizations"} class="flex items-center gap-2">
            <.icon name="hero-building-office" class="size-4" /> Organizations
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/memberships"} class="flex items-center gap-2">
            <.icon name="hero-user-group" class="size-4" /> Memberships
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/apis"} class="flex items-center gap-2">
            <.icon name="hero-bolt" class="size-4" /> APIs
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/subscriptions"} class="flex items-center gap-2">
            <.icon name="hero-credit-card" class="size-4" /> Subscriptions
          </.link>
        </li>
        <li class="menu-title mt-3">API Data</li>
        <li>
          <.link href={~p"/admin/api-keys"} class="flex items-center gap-2">
            <.icon name="hero-key" class="size-4" /> API Keys
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/api-conversations"} class="flex items-center gap-2">
            <.icon name="hero-chat-bubble-left-right" class="size-4" /> Conversations
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/data-store-entries"} class="flex items-center gap-2">
            <.icon name="hero-circle-stack" class="size-4" /> Data Store
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/invocation-logs"} class="flex items-center gap-2">
            <.icon name="hero-arrow-path" class="size-4" /> Invocation Logs
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/metric-rollups"} class="flex items-center gap-2">
            <.icon name="hero-chart-bar" class="size-4" /> Metric Rollups
          </.link>
        </li>
        <li class="menu-title mt-3">Billing</li>
        <li>
          <.link href={~p"/admin/daily-usage"} class="flex items-center gap-2">
            <.icon name="hero-calendar-days" class="size-4" /> Daily Usage
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/usage-events"} class="flex items-center gap-2">
            <.icon name="hero-signal" class="size-4" /> Usage Events
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/processed-events"} class="flex items-center gap-2">
            <.icon name="hero-check-badge" class="size-4" /> Processed Events
          </.link>
        </li>
        <li class="menu-title mt-3">Testing</li>
        <li>
          <.link href={~p"/admin/test-requests"} class="flex items-center gap-2">
            <.icon name="hero-beaker" class="size-4" /> Test Requests
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/test-suites"} class="flex items-center gap-2">
            <.icon name="hero-clipboard-document-check" class="size-4" /> Test Suites
          </.link>
        </li>
        <li class="menu-title mt-3">LLM & Audit</li>
        <li>
          <.link href={~p"/admin/llm-usage"} class="flex items-center gap-2">
            <.icon name="hero-cpu-chip" class="size-4" /> LLM Usage
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/audit-logs"} class="flex items-center gap-2">
            <.icon name="hero-document-text" class="size-4" /> Audit Logs
          </.link>
        </li>
        <li>
          <.link href={~p"/admin/versions"} class="flex items-center gap-2">
            <.icon name="hero-clock" class="size-4" /> Versions
          </.link>
        </li>
      </:sidebar>
      {render_slot(@inner_block)}
      {render_slot(@inner_content)}
    </Backpex.HTML.Layout.app_shell>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-accent hover:text-accent-foreground"
    >
      <.icon name={@icon} class="size-4" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp toggle_mobile_menu do
    JS.toggle(to: "#mobile-menu")
    |> JS.toggle(to: "#mobile-menu-open")
    |> JS.toggle(to: "#mobile-menu-close")
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
