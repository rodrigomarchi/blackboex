defmodule BlackboexWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BlackboexWeb, :html

  # Embed all .heex templates from this directory.
  embed_templates "./*"

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
          <.nav_link navigate={~p"/dashboard"} icon="hero-home" icon_class="size-4 text-accent-sky">
            Dashboard
          </.nav_link>
          <.nav_link navigate={~p"/apis"} icon="hero-bolt" icon_class="size-4 text-accent-amber">
            APIs
          </.nav_link>
          <.nav_link
            navigate={~p"/flows"}
            icon="hero-arrow-path"
            icon_class="size-4 text-accent-violet"
          >
            Flows
          </.nav_link>
          <.nav_link navigate={~p"/api-keys"} icon="hero-key" icon_class="size-4 text-accent-amber">
            API Keys
          </.nav_link>
          <.nav_link
            navigate={~p"/billing"}
            icon="hero-credit-card"
            icon_class="size-4 text-accent-emerald"
          >
            Billing
          </.nav_link>
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
              <.icon name="hero-cog-6-tooth" class="size-4 text-slate-400" />
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
          <.button
            type="button"
            variant="ghost"
            size="icon"
            class="h-auto w-auto p-2 md:hidden"
            phx-click={toggle_mobile_menu()}
          >
            <span id="mobile-menu-open"><.icon name="hero-bars-3" class="size-5" /></span>
            <span id="mobile-menu-close" class="hidden">
              <.icon name="hero-x-mark" class="size-5" />
            </span>
          </.button>
        </div>
      </header>

      <%!-- Mobile menu (hidden by default) --%>
      <div id="mobile-menu" class="hidden border-b bg-card px-4 py-3 md:hidden">
        <nav class="flex flex-col gap-1">
          <.nav_link navigate={~p"/dashboard"} icon="hero-home" icon_class="size-4 text-accent-sky">
            Dashboard
          </.nav_link>
          <.nav_link navigate={~p"/apis"} icon="hero-bolt" icon_class="size-4 text-accent-amber">
            APIs
          </.nav_link>
          <.nav_link
            navigate={~p"/flows"}
            icon="hero-arrow-path"
            icon_class="size-4 text-accent-violet"
          >
            Flows
          </.nav_link>
          <.nav_link navigate={~p"/api-keys"} icon="hero-key" icon_class="size-4 text-accent-amber">
            API Keys
          </.nav_link>
          <.nav_link
            navigate={~p"/billing"}
            icon="hero-credit-card"
            icon_class="size-4 text-accent-emerald"
          >
            Billing
          </.nav_link>
          <.nav_link
            navigate={~p"/settings"}
            icon="hero-cog-6-tooth"
            icon_class="size-4 text-slate-400"
          >
            Settings
          </.nav_link>
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

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :icon_class, :string, default: "size-4"
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-accent hover:text-accent-foreground"
    >
      <.icon name={@icon} class={@icon_class} />
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
    <div class="relative flex flex-row items-center border-2 border-border bg-muted rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border border-border bg-background left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <.button
        type="button"
        variant="ghost"
        size="icon"
        class="flex h-auto w-1/3 cursor-pointer rounded-none p-2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </.button>

      <.button
        type="button"
        variant="ghost"
        size="icon"
        class="flex h-auto w-1/3 cursor-pointer rounded-none p-2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </.button>

      <.button
        type="button"
        variant="ghost"
        size="icon"
        class="flex h-auto w-1/3 cursor-pointer rounded-none p-2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </.button>
    </div>
    """
  end
end
