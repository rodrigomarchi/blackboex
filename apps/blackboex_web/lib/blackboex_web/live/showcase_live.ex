defmodule BlackboexWeb.ShowcaseLive do
  @moduledoc "Design system showcase — visual documentation for all UI components."
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Modal

  @sections [
    # Foundation
    {"tokens", "Design Tokens", :foundation},
    {"typography", "Typography", :foundation},
    # UI
    {"button", "Button", :ui},
    {"badge", "Badge", :ui},
    {"card", "Card", :ui},
    {"input", "Input", :ui},
    {"label", "Label", :ui},
    {"field-label", "Field Label", :ui},
    {"modal", "Modal", :ui},
    {"tabs", "Tabs", :ui},
    {"tooltip", "Tooltip", :ui},
    {"dropdown-menu", "Dropdown Menu", :ui},
    {"table", "Table", :ui},
    {"separator", "Separator", :ui},
    {"spinner", "Spinner", :ui},
    {"skeleton", "Skeleton", :ui},
    {"status-dot", "Status Dot", :ui},
    {"alert-banner", "Alert Banner", :ui},
    {"action-row", "Action Row", :ui},
    {"section-heading", "Section Heading", :ui},
    {"header", "Header", :ui},
    {"icon", "Icon", :ui},
    # Shared
    {"stat-card", "Stat Card", :shared},
    {"stat-mini", "Stat Mini", :shared},
    {"stat-grid", "Stat Grid", :shared},
    {"panel", "Panel", :shared},
    {"page", "Page", :shared},
    {"empty-state", "Empty State", :shared},
    {"list-row", "List Row", :shared},
    {"form-actions", "Form Actions", :shared},
    {"editor-tab-panel", "Editor Tab Panel", :shared},
    {"chart-grid", "Chart Grid", :shared},
    {"category-pills", "Category Pills", :shared},
    {"underline-tabs", "Underline Tabs", :shared},
    {"dashboard-nav", "Dashboard Nav", :shared},
    {"description-list", "Description List", :shared},
    {"progress-bar", "Progress Bar", :shared},
    {"icon-badge", "Icon Badge", :shared},
    {"inline-code", "Inline Code", :shared}
  ]

  @section_modules %{
    "tokens" => BlackboexWeb.Showcase.Sections.Tokens,
    "typography" => BlackboexWeb.Showcase.Sections.Typography,
    "button" => BlackboexWeb.Showcase.Sections.Button,
    "badge" => BlackboexWeb.Showcase.Sections.Badge,
    "card" => BlackboexWeb.Showcase.Sections.Card,
    "input" => BlackboexWeb.Showcase.Sections.Input,
    "label" => BlackboexWeb.Showcase.Sections.Label,
    "field-label" => BlackboexWeb.Showcase.Sections.FieldLabel,
    "modal" => BlackboexWeb.Showcase.Sections.Modal,
    "tabs" => BlackboexWeb.Showcase.Sections.Tabs,
    "tooltip" => BlackboexWeb.Showcase.Sections.Tooltip,
    "dropdown-menu" => BlackboexWeb.Showcase.Sections.DropdownMenu,
    "table" => BlackboexWeb.Showcase.Sections.DataTable,
    "separator" => BlackboexWeb.Showcase.Sections.Separator,
    "spinner" => BlackboexWeb.Showcase.Sections.Spinner,
    "skeleton" => BlackboexWeb.Showcase.Sections.Skeleton,
    "status-dot" => BlackboexWeb.Showcase.Sections.StatusDot,
    "alert-banner" => BlackboexWeb.Showcase.Sections.AlertBanner,
    "action-row" => BlackboexWeb.Showcase.Sections.ActionRow,
    "section-heading" => BlackboexWeb.Showcase.Sections.SectionHeading,
    "header" => BlackboexWeb.Showcase.Sections.PageHeader,
    "icon" => BlackboexWeb.Showcase.Sections.IconShowcase,
    "stat-card" => BlackboexWeb.Showcase.Sections.StatCard,
    "stat-mini" => BlackboexWeb.Showcase.Sections.StatMini,
    "stat-grid" => BlackboexWeb.Showcase.Sections.StatGrid,
    "panel" => BlackboexWeb.Showcase.Sections.PanelShowcase,
    "page" => BlackboexWeb.Showcase.Sections.PageShowcase,
    "empty-state" => BlackboexWeb.Showcase.Sections.EmptyState,
    "list-row" => BlackboexWeb.Showcase.Sections.ListRow,
    "form-actions" => BlackboexWeb.Showcase.Sections.FormActions,
    "editor-tab-panel" => BlackboexWeb.Showcase.Sections.EditorTabPanel,
    "chart-grid" => BlackboexWeb.Showcase.Sections.ChartGrid,
    "category-pills" => BlackboexWeb.Showcase.Sections.CategoryPills,
    "underline-tabs" => BlackboexWeb.Showcase.Sections.UnderlineTabs,
    "dashboard-nav" => BlackboexWeb.Showcase.Sections.DashboardNav,
    "description-list" => BlackboexWeb.Showcase.Sections.DescriptionList,
    "progress-bar" => BlackboexWeb.Showcase.Sections.ProgressBar,
    "icon-badge" => BlackboexWeb.Showcase.Sections.IconBadge,
    "inline-code" => BlackboexWeb.Showcase.Sections.InlineCode
  }

  @valid_slugs MapSet.new(Map.keys(@section_modules))

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, section: "tokens", show_modal: false)}
  end

  @impl true
  def handle_params(%{"section" => section}, _uri, socket) do
    if section in @valid_slugs do
      {:noreply,
       assign(socket,
         section: section,
         page_title: section_title(section) <> " — Showcase"
       )}
    else
      {:noreply, push_navigate(socket, to: ~p"/showcase/tokens")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/showcase/tokens")}
  end

  @impl true
  def handle_event("open_modal", _, socket), do: {:noreply, assign(socket, show_modal: true)}
  def handle_event("close_modal", _, socket), do: {:noreply, assign(socket, show_modal: false)}
  def handle_event("noop", _, socket), do: {:noreply, socket}
  def handle_event(_, _, socket), do: {:noreply, socket}

  defp section_title(slug) do
    case Enum.find(@sections, fn {s, _, _} -> s == slug end) do
      {_, title, _} -> title
      _ -> slug
    end
  end

  defp sections_by_category do
    Enum.group_by(@sections, fn {_, _, cat} -> cat end)
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:sections_by_cat, sections_by_category())
      |> assign(:section_module, @section_modules[assigns.section])

    ~H"""
    <div class="flex h-screen overflow-hidden">
      <%!-- Sidebar --%>
      <aside class="w-52 shrink-0 border-r bg-card flex flex-col overflow-y-auto">
        <div class="px-4 py-3 border-b shrink-0">
          <p class="text-sm font-semibold">Design System</p>
          <p class="text-2xs text-muted-foreground">Component Showcase</p>
        </div>
        <nav class="p-2 flex-1 overflow-y-auto py-3 space-y-4">
          <div>
            <p class="px-2 mb-1 text-2xs font-medium text-muted-foreground uppercase tracking-wider">
              Foundation
            </p>
            <%= for {slug, title, _} <- @sections_by_cat[:foundation] || [] do %>
              <.link
                navigate={~p"/showcase/#{slug}"}
                class={[
                  "flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors",
                  @section == slug && "bg-accent text-accent-foreground font-medium",
                  @section != slug &&
                    "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
                ]}
              >
                {title}
              </.link>
            <% end %>
          </div>
          <div>
            <p class="px-2 mb-1 text-2xs font-medium text-muted-foreground uppercase tracking-wider">
              UI Components
            </p>
            <%= for {slug, title, _} <- @sections_by_cat[:ui] || [] do %>
              <.link
                navigate={~p"/showcase/#{slug}"}
                class={[
                  "flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors",
                  @section == slug && "bg-accent text-accent-foreground font-medium",
                  @section != slug &&
                    "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
                ]}
              >
                {title}
              </.link>
            <% end %>
          </div>
          <div>
            <p class="px-2 mb-1 text-2xs font-medium text-muted-foreground uppercase tracking-wider">
              Shared
            </p>
            <%= for {slug, title, _} <- @sections_by_cat[:shared] || [] do %>
              <.link
                navigate={~p"/showcase/#{slug}"}
                class={[
                  "flex items-center gap-2 px-2 py-1.5 rounded-md text-sm transition-colors",
                  @section == slug && "bg-accent text-accent-foreground font-medium",
                  @section != slug &&
                    "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
                ]}
              >
                {title}
              </.link>
            <% end %>
          </div>
        </nav>
        <div class="p-3 border-t shrink-0">
          <Layouts.theme_toggle {assigns} />
        </div>
      </aside>

      <%!-- Content --%>
      <main class="flex-1 overflow-y-auto">
        <div class="max-w-4xl mx-auto p-8 space-y-12">
          {@section_module.render(assigns)}
        </div>
      </main>

      <%!-- Modal (for modal section demo) --%>
      <.modal :if={@show_modal} show={@show_modal} on_close="close_modal" title="Example Modal">
        <p class="text-sm text-muted-foreground">
          This is example modal content. Modals are rendered with a backdrop and support a close action.
        </p>
        <div class="mt-4 flex justify-end gap-2">
          <.button variant="outline" phx-click="close_modal">Cancel</.button>
          <.button variant="primary" phx-click="close_modal">Confirm</.button>
        </div>
      </.modal>
    </div>
    """
  end
end
