defmodule BlackboexWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BlackboexWeb, :html

  import BlackboexWeb.Components.AppSidebar

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

  attr :current_path, :string,
    default: nil,
    doc: "the current URL path for sidebar active state"

  def app(assigns) do
    ~H"""
    <div class="flex h-screen">
      <%!-- Sidebar (hidden on mobile, visible on md+) --%>
      <div class="hidden md:flex">
        <.sidebar
          id="app-sidebar-desktop"
          current_scope={@current_scope}
          current_path={@current_path}
        />
      </div>

      <div class="flex flex-1 flex-col overflow-hidden">
        <%!-- Mobile header --%>
        <header class="flex h-14 shrink-0 items-center border-b bg-card px-4 md:hidden">
          <.logo_full class="h-6" />
          <div class="flex-1" />
          <.button
            type="button"
            variant="ghost"
            size="icon"
            class="h-auto w-auto p-2"
            phx-click={toggle_mobile_menu()}
          >
            <span id="mobile-menu-open"><.icon name="hero-bars-3" class="size-5" /></span>
            <span id="mobile-menu-close" class="hidden">
              <.icon name="hero-x-mark" class="size-5" />
            </span>
          </.button>
        </header>

        <%!-- Mobile sidebar overlay --%>
        <div id="mobile-menu" class="hidden border-b bg-card md:hidden">
          <.sidebar
            id="app-sidebar-mobile"
            current_scope={@current_scope}
            current_path={@current_path}
          />
        </div>

        <main class="flex-1 overflow-y-auto px-4 py-6 md:px-6 md:py-8">
          <div class="mx-auto max-w-6xl">
            {@inner_content}
          </div>
        </main>
      </div>
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

  attr :current_path, :string,
    default: nil,
    doc: "the current URL path for sidebar active state"

  def editor(assigns) do
    assigns = assign(assigns, :hide_editor_sidebar, hide_editor_sidebar?(assigns))

    ~H"""
    <div class="flex h-screen overflow-hidden bg-background text-foreground">
      <%!-- Collapsed sidebar icon strip --%>
      <div :if={!@hide_editor_sidebar} class="hidden md:flex">
        <.sidebar
          id="editor-sidebar"
          current_scope={@current_scope}
          current_path={@current_path}
          collapsed={true}
        />
      </div>
      <div class="flex-1 overflow-hidden">
        {@inner_content}
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # Full-screen editors hide the side nav to maximize canvas real-estate.
  # The match covers project-scoped paths too (e.g.
  # `/orgs/:slug/projects/:slug/flows/:id/edit`), not only the top-level
  # `/flows/:id/edit` legacy route.
  defp hide_editor_sidebar?(%{current_path: path}) when is_binary(path) do
    Regex.match?(~r{/flows/[^/]+/edit(?:\?.*)?$}, path)
  end

  defp hide_editor_sidebar?(_), do: false

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

  @doc "Design system showcase layout — minimal shell, no auth, dev-only."
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil

  def showcase(assigns) do
    ~H"""
    <div class="h-screen bg-background text-foreground overflow-hidden">
      {@inner_content}
    </div>
    <.flash_group flash={@flash} />
    """
  end
end
