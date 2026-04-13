defmodule BlackboexWeb.Components.FlowEditor.PropertiesDrawer do
  @moduledoc """
  Properties drawer panel for the flow editor.
  Renders the side panel that appears when a node is selected.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.FlowEditor.NodeProperties
  import BlackboexWeb.Components.Shared.CodeEditorField

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

  def properties_drawer(%{node: %{type: "exec_data"}} = assigns) do
    json =
      case assigns.node.data do
        %{"output" => output} when not is_nil(output) ->
          Jason.encode!(output, pretty: true)

        _ ->
          "{}"
      end

    assigns = assign(assigns, json: json)

    ~H"""
    <aside class="flex w-96 shrink-0 flex-col border-l bg-card animate-in slide-in-from-right duration-200">
      <div class="flex items-center justify-between border-b px-4 py-3">
        <div class="flex items-center gap-2">
          <div class="flex size-7 items-center justify-center rounded-lg bg-accent-violet/10 text-accent-violet">
            <.icon name="hero-document-text" class="size-3.5" />
          </div>
          <span class="text-sm font-semibold">Execution Data</span>
        </div>
        <.button variant="ghost-muted" size="icon-sm" phx-click="close_drawer">
          <.icon name="hero-x-mark" class="size-4" />
        </.button>
      </div>
      <div class="flex-1 overflow-y-auto p-4">
        <.code_editor_field
          id={"exec-data-viewer-#{@node.id}"}
          value={@json}
          max_height="max-h-[80vh]"
          class="w-full rounded-lg"
        />
      </div>
    </aside>
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
          <.button
            variant="ghost-muted"
            size="icon-sm"
            phx-click="toggle_drawer_expand"
            title={if @expanded, do: "Collapse", else: "Expand"}
          >
            <.icon
              name={if @expanded, do: "hero-arrows-pointing-in", else: "hero-arrows-pointing-out"}
              class="size-4"
            />
          </.button>
          <.button
            variant="ghost-muted"
            size="icon-sm"
            phx-click="close_drawer"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </.button>
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
