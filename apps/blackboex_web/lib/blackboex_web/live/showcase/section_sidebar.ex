defmodule BlackboexWeb.Showcase.Sections.SidebarShowcase do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Editor.CodeViewer
  import BlackboexWeb.Components.Sidebar

  @code_basic ~S"""
  <.sidebar_provider>
    <.sidebar id="demo-sidebar" side="left" collapsible="none" state="expanded">
      <.sidebar_header>
        <span class="font-semibold text-sm px-2">My App</span>
      </.sidebar_header>
      <.sidebar_content>
        <.sidebar_menu>
          <.sidebar_menu_item>
            <.sidebar_menu_button is_active>
              <.icon name="hero-home" class="size-4" />
              <span>Dashboard</span>
            </.sidebar_menu_button>
          </.sidebar_menu_item>
          <.sidebar_menu_item>
            <.sidebar_menu_button>
              <.icon name="hero-document-text" class="size-4" />
              <span>APIs</span>
            </.sidebar_menu_button>
          </.sidebar_menu_item>
          <.sidebar_menu_item>
            <.sidebar_menu_button>
              <.icon name="hero-cog-6-tooth" class="size-4" />
              <span>Settings</span>
            </.sidebar_menu_button>
          </.sidebar_menu_item>
        </.sidebar_menu>
      </.sidebar_content>
      <.sidebar_footer>
        <span class="text-xs text-muted-foreground px-2">v1.0.0</span>
      </.sidebar_footer>
    </.sidebar>
    <.sidebar_inset>
      <p class="p-4 text-sm text-muted-foreground">Main content area</p>
    </.sidebar_inset>
  </.sidebar_provider>
  """

  @code_variant_sidebar ~S"""
  <%!-- variant="sidebar" — default, flush panel attached to the edge --%>
  <.sidebar id="s1" variant="sidebar" collapsible="offcanvas">
    ...
  </.sidebar>
  """

  @code_variant_floating ~S"""
  <%!-- variant="floating" — rounded panel floating above the content --%>
  <.sidebar id="s2" variant="floating" collapsible="icon">
    ...
  </.sidebar>
  """

  @code_variant_inset ~S"""
  <%!-- variant="inset" — sidebar_inset gets rounded card treatment --%>
  <.sidebar id="s3" variant="inset" collapsible="offcanvas">
    ...
  </.sidebar>
  <.sidebar_inset>
    <%!-- This area gets rounded-xl + shadow when variant=inset --%>
    ...
  </.sidebar_inset>
  """

  @code_menu_actions ~S"""
  <.sidebar_menu_item>
    <.sidebar_menu_button>
      <.icon name="hero-folder" class="size-4" />
      <span>Projects</span>
    </.sidebar_menu_button>
    <.sidebar_menu_action show_on_hover phx-click="open_menu">
      <.icon name="hero-ellipsis-horizontal" class="size-4" />
    </.sidebar_menu_action>
    <.sidebar_menu_badge>3</.sidebar_menu_badge>
  </.sidebar_menu_item>
  """

  @code_submenu ~S"""
  <.sidebar_menu_item>
    <.sidebar_menu_button>
      <.icon name="hero-rectangle-stack" class="size-4" />
      <span>Components</span>
    </.sidebar_menu_button>
    <.sidebar_menu_sub>
      <.sidebar_menu_sub_item>
        <.sidebar_menu_sub_button is_active>Button</.sidebar_menu_sub_button>
      </.sidebar_menu_sub_item>
      <.sidebar_menu_sub_item>
        <.sidebar_menu_sub_button>Card</.sidebar_menu_sub_button>
      </.sidebar_menu_sub_item>
      <.sidebar_menu_sub_item>
        <.sidebar_menu_sub_button size="sm">Input (sm)</.sidebar_menu_sub_button>
      </.sidebar_menu_sub_item>
    </.sidebar_menu_sub>
  </.sidebar_menu_item>
  """

  @code_skeleton ~S"""
  <%!-- Without icon --%>
  <.sidebar_menu_skeleton />

  <%!-- With icon placeholder --%>
  <.sidebar_menu_skeleton show_icon />
  """

  @code_search_input ~S"""
  <.sidebar_header>
    <.sidebar_input placeholder="Search..." />
  </.sidebar_header>
  """

  @code_collapsible_offcanvas ~S"""
  <%!-- offcanvas: sidebar slides out off-screen when collapsed --%>
  <.sidebar id="s1" collapsible="offcanvas" state="expanded">
    ...
  </.sidebar>
  """

  @code_collapsible_icon ~S"""
  <%!-- icon: sidebar shrinks to icon-only width when collapsed --%>
  <.sidebar id="s2" collapsible="icon" state="expanded">
    ...
  </.sidebar>
  """

  @code_collapsible_none ~S"""
  <%!-- none: sidebar is always visible, cannot be collapsed --%>
  <.sidebar id="s3" collapsible="none">
    ...
  </.sidebar>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_basic, @code_basic)
      |> assign(:code_variant_sidebar, @code_variant_sidebar)
      |> assign(:code_variant_floating, @code_variant_floating)
      |> assign(:code_variant_inset, @code_variant_inset)
      |> assign(:code_menu_actions, @code_menu_actions)
      |> assign(:code_submenu, @code_submenu)
      |> assign(:code_skeleton, @code_skeleton)
      |> assign(:code_search_input, @code_search_input)
      |> assign(:code_collapsible_offcanvas, @code_collapsible_offcanvas)
      |> assign(:code_collapsible_icon, @code_collapsible_icon)
      |> assign(:code_collapsible_none, @code_collapsible_none)

    ~H"""
    <.section_header
      title="Sidebar"
      description="Full-featured collapsible sidebar built on SaladUI. sidebar_provider wraps the layout; sidebar is the panel itself; sidebar_inset holds the main content. Multiple sub-components handle navigation items, actions, badges, and loading states."
      module="BlackboexWeb.Components.Sidebar"
    />
    <div class="space-y-10">
      <%!-- Block 1: Basic Sidebar (expanded) --%>
      <.showcase_block title="Basic Sidebar (expanded)" code={@code_basic}>
        <div class="h-96 border rounded-lg overflow-hidden flex relative">
          <.sidebar_provider>
            <.sidebar id="showcase-sidebar-1" side="left" collapsible="none" state="expanded">
              <.sidebar_header>
                <span class="font-semibold text-sm px-2">My App</span>
              </.sidebar_header>
              <.sidebar_content>
                <.sidebar_menu>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button is_active>
                      <.icon name="hero-home" class="size-4" />
                      <span>Dashboard</span>
                    </.sidebar_menu_button>
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button>
                      <.icon name="hero-document-text" class="size-4" />
                      <span>APIs</span>
                    </.sidebar_menu_button>
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button>
                      <.icon name="hero-cog-6-tooth" class="size-4" />
                      <span>Settings</span>
                    </.sidebar_menu_button>
                  </.sidebar_menu_item>
                </.sidebar_menu>
              </.sidebar_content>
              <.sidebar_footer>
                <span class="text-xs text-muted-foreground px-2">v1.0.0</span>
              </.sidebar_footer>
            </.sidebar>
            <.sidebar_inset>
              <p class="p-4 text-sm text-muted-foreground">Main content area</p>
            </.sidebar_inset>
          </.sidebar_provider>
        </div>
      </.showcase_block>

      <%!-- Block 2: Sidebar variants (code only) --%>
      <.showcase_block
        title="Sidebar variants — sidebar / floating / inset"
        code={@code_variant_sidebar}
      >
        <div class="grid grid-cols-3 gap-4">
          <div>
            <p class="text-xs font-semibold text-muted-foreground mb-2 uppercase tracking-wider">
              variant="sidebar"
            </p>
            <p class="text-xs text-muted-foreground">Default flush panel attached to the edge.</p>
          </div>
          <div>
            <p class="text-xs font-semibold text-muted-foreground mb-2 uppercase tracking-wider">
              variant="floating"
            </p>
            <p class="text-xs text-muted-foreground">
              Rounded panel floating with border and shadow.
            </p>
          </div>
          <div>
            <p class="text-xs font-semibold text-muted-foreground mb-2 uppercase tracking-wider">
              variant="inset"
            </p>
            <p class="text-xs text-muted-foreground">
              sidebar_inset gets rounded-xl + shadow treatment.
            </p>
          </div>
        </div>
      </.showcase_block>

      <div class="space-y-2 -mt-6">
        <div class="rounded-lg overflow-hidden border">
          <.code_viewer code={@code_variant_floating} label="floating" />
        </div>
        <div class="rounded-lg overflow-hidden border">
          <.code_viewer code={@code_variant_inset} label="inset" />
        </div>
      </div>

      <%!-- Block 3: Menu with actions --%>
      <.showcase_block title="Menu with actions" code={@code_menu_actions}>
        <div class="h-64 border rounded-lg overflow-hidden flex relative">
          <.sidebar_provider>
            <.sidebar id="showcase-sidebar-2" side="left" collapsible="none" state="expanded">
              <.sidebar_content>
                <.sidebar_menu>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button>
                      <.icon name="hero-folder" class="size-4" />
                      <span>Projects</span>
                    </.sidebar_menu_button>
                    <.sidebar_menu_action show_on_hover>
                      <.icon name="hero-ellipsis-horizontal" class="size-4" />
                    </.sidebar_menu_action>
                    <.sidebar_menu_badge>3</.sidebar_menu_badge>
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button is_active>
                      <.icon name="hero-bolt" class="size-4" />
                      <span>Flows</span>
                    </.sidebar_menu_button>
                    <.sidebar_menu_action show_on_hover>
                      <.icon name="hero-ellipsis-horizontal" class="size-4" />
                    </.sidebar_menu_action>
                    <.sidebar_menu_badge>12</.sidebar_menu_badge>
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button>
                      <.icon name="hero-key" class="size-4" />
                      <span>API Keys</span>
                    </.sidebar_menu_button>
                    <.sidebar_menu_action show_on_hover>
                      <.icon name="hero-ellipsis-horizontal" class="size-4" />
                    </.sidebar_menu_action>
                  </.sidebar_menu_item>
                </.sidebar_menu>
              </.sidebar_content>
            </.sidebar>
            <.sidebar_inset>
              <p class="p-4 text-xs text-muted-foreground">Hover a row to see the action button</p>
            </.sidebar_inset>
          </.sidebar_provider>
        </div>
      </.showcase_block>

      <%!-- Block 4: Sub-menu --%>
      <.showcase_block title="Sub-menu" code={@code_submenu}>
        <div class="h-72 border rounded-lg overflow-hidden flex relative">
          <.sidebar_provider>
            <.sidebar id="showcase-sidebar-3" side="left" collapsible="none" state="expanded">
              <.sidebar_content>
                <.sidebar_menu>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button>
                      <.icon name="hero-home" class="size-4" />
                      <span>Dashboard</span>
                    </.sidebar_menu_button>
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button>
                      <.icon name="hero-rectangle-stack" class="size-4" />
                      <span>Components</span>
                    </.sidebar_menu_button>
                    <.sidebar_menu_sub>
                      <.sidebar_menu_sub_item>
                        <.sidebar_menu_sub_button is_active>Button</.sidebar_menu_sub_button>
                      </.sidebar_menu_sub_item>
                      <.sidebar_menu_sub_item>
                        <.sidebar_menu_sub_button>Card</.sidebar_menu_sub_button>
                      </.sidebar_menu_sub_item>
                      <.sidebar_menu_sub_item>
                        <.sidebar_menu_sub_button size="sm">Input (sm)</.sidebar_menu_sub_button>
                      </.sidebar_menu_sub_item>
                    </.sidebar_menu_sub>
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button>
                      <.icon name="hero-cog-6-tooth" class="size-4" />
                      <span>Settings</span>
                    </.sidebar_menu_button>
                  </.sidebar_menu_item>
                </.sidebar_menu>
              </.sidebar_content>
            </.sidebar>
            <.sidebar_inset>
              <p class="p-4 text-xs text-muted-foreground">Nested sub-menu with border-l</p>
            </.sidebar_inset>
          </.sidebar_provider>
        </div>
      </.showcase_block>

      <%!-- Block 5: Skeleton loading --%>
      <.showcase_block title="Skeleton loading" code={@code_skeleton}>
        <div class="h-56 border rounded-lg overflow-hidden flex relative">
          <.sidebar_provider>
            <.sidebar id="showcase-sidebar-4" side="left" collapsible="none" state="expanded">
              <.sidebar_content>
                <.sidebar_menu>
                  <.sidebar_menu_item>
                    <.sidebar_menu_skeleton />
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_skeleton />
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_skeleton show_icon />
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_skeleton show_icon />
                  </.sidebar_menu_item>
                </.sidebar_menu>
              </.sidebar_content>
            </.sidebar>
            <.sidebar_inset>
              <p class="p-4 text-xs text-muted-foreground">Loading state placeholder</p>
            </.sidebar_inset>
          </.sidebar_provider>
        </div>
      </.showcase_block>

      <%!-- Block 6: With search input --%>
      <.showcase_block title="With search input" code={@code_search_input}>
        <div class="h-72 border rounded-lg overflow-hidden flex relative">
          <.sidebar_provider>
            <.sidebar id="showcase-sidebar-5" side="left" collapsible="none" state="expanded">
              <.sidebar_header>
                <span class="font-semibold text-sm px-2">My App</span>
                <.sidebar_input placeholder="Search..." />
              </.sidebar_header>
              <.sidebar_content>
                <.sidebar_menu>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button is_active>
                      <.icon name="hero-home" class="size-4" />
                      <span>Dashboard</span>
                    </.sidebar_menu_button>
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button>
                      <.icon name="hero-document-text" class="size-4" />
                      <span>APIs</span>
                    </.sidebar_menu_button>
                  </.sidebar_menu_item>
                  <.sidebar_menu_item>
                    <.sidebar_menu_button>
                      <.icon name="hero-bolt" class="size-4" />
                      <span>Flows</span>
                    </.sidebar_menu_button>
                  </.sidebar_menu_item>
                </.sidebar_menu>
              </.sidebar_content>
            </.sidebar>
            <.sidebar_inset>
              <p class="p-4 text-xs text-muted-foreground">Search input in header</p>
            </.sidebar_inset>
          </.sidebar_provider>
        </div>
      </.showcase_block>

      <%!-- Block 7: Collapsible modes (code only) --%>
      <.showcase_block title="Collapsible modes (code)">
        <div class="grid grid-cols-3 gap-6">
          <div>
            <p class="text-xs font-semibold text-muted-foreground mb-1 uppercase tracking-wider">
              offcanvas
            </p>
            <p class="text-xs text-muted-foreground">
              Slides entirely off-screen. Width goes to zero when collapsed.
            </p>
          </div>
          <div>
            <p class="text-xs font-semibold text-muted-foreground mb-1 uppercase tracking-wider">
              icon
            </p>
            <p class="text-xs text-muted-foreground">
              Shrinks to icon-only width (--sidebar-width-icon). Labels hide.
            </p>
          </div>
          <div>
            <p class="text-xs font-semibold text-muted-foreground mb-1 uppercase tracking-wider">
              none
            </p>
            <p class="text-xs text-muted-foreground">
              Always visible. No toggle. sidebar_trigger and sidebar_rail are no-ops.
            </p>
          </div>
        </div>
      </.showcase_block>

      <div class="space-y-2 -mt-6">
        <div class="rounded-lg overflow-hidden border">
          <.code_viewer code={@code_collapsible_offcanvas} label="offcanvas" />
        </div>
        <div class="rounded-lg overflow-hidden border">
          <.code_viewer code={@code_collapsible_icon} label="icon" />
        </div>
        <div class="rounded-lg overflow-hidden border">
          <.code_viewer code={@code_collapsible_none} label="none" />
        </div>
      </div>
    </div>
    """
  end
end
