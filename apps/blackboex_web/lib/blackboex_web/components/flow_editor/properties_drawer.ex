defmodule BlackboexWeb.Components.FlowEditor.PropertiesDrawer do
  @moduledoc """
  Properties drawer panel for the flow editor.
  Renders the side panel that appears when a node is selected.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.FlowEditor.NodeProperties

  attr :node, :map, default: nil
  attr :tab, :string, default: "settings"
  attr :expanded, :boolean, default: false
  attr :state_variables, :list, default: []
  attr :org_flows, :list, default: []
  attr :sub_flow_schema, :list, default: []

  def properties_drawer(%{node: nil} = assigns) do
    ~H"""
    """
  end

  def properties_drawer(assigns) do
    width_class = if assigns.expanded, do: "w-[70vw]", else: "w-96"

    assigns = assign(assigns, width_class: width_class)

    ~H"""
    <aside class={"flex shrink-0 flex-col border-l bg-card animate-in slide-in-from-right duration-200 #{@width_class} transition-[width] ease-in-out"}>
      <%!-- Drawer header --%>
      <div class="flex items-center justify-between border-b px-4 py-3">
        <div class="flex items-center gap-2">
          <div
            class="flex size-7 items-center justify-center rounded-lg"
            style={"background: #{@node.color}15; color: #{@node.color}"}
          >
            <.icon name={@node.icon} class="size-3.5" />
          </div>
          <span class="text-sm font-semibold">{@node.label}</span>
        </div>
        <div class="flex items-center gap-1">
          <button
            phx-click="toggle_drawer_expand"
            class="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
            title={if @expanded, do: "Collapse", else: "Expand"}
          >
            <.icon
              name={if @expanded, do: "hero-arrows-pointing-in", else: "hero-arrows-pointing-out"}
              class="size-4"
            />
          </button>
          <button
            phx-click="close_drawer"
            class="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
      </div>

      <%!-- Drawer body --%>
      <div class="flex-1 overflow-y-auto p-4 space-y-4">
        <.node_properties
          type={@node.type}
          data={@node.data}
          node_id={@node.id}
          tab={@tab}
          state_variables={@state_variables}
          org_flows={@org_flows}
          sub_flow_schema={@sub_flow_schema}
        />
      </div>
    </aside>
    """
  end
end
