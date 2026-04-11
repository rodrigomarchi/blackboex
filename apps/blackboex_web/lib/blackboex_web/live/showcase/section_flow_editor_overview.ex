defmodule BlackboexWeb.Showcase.Sections.FlowEditorOverview do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  @components [
    %{
      name: "FlowHeader",
      module: "BlackboexWeb.Components.FlowEditor.FlowHeader",
      description: "Flow editor header bar. Shows flow name, status badge, webhook URL, and save/run/JSON action buttons.",
      complex: false
    },
    %{
      name: "JsonPreviewModal",
      module: "BlackboexWeb.Components.FlowEditor.JsonPreviewModal",
      description: "Modal for previewing the JSON representation of a flow definition. Includes copy and download actions.",
      complex: false
    },
    %{
      name: "RunModal",
      module: "BlackboexWeb.Components.FlowEditor.RunModal",
      description: "Modal for manually running a flow with JSON test input. Shows result and error output.",
      complex: false
    },
    %{
      name: "NodePalette",
      module: "BlackboexWeb.Components.FlowEditor.NodePalette",
      description: "Draggable node types panel for adding trigger, action, and condition nodes to the flow canvas.",
      complex: true
    },
    %{
      name: "NodeProperties",
      module: "BlackboexWeb.Components.FlowEditor.NodeProperties",
      description: "Properties editor for the currently selected node. Form fields vary by node type.",
      complex: true
    },
    %{
      name: "PropertiesDrawer",
      module: "BlackboexWeb.Components.FlowEditor.PropertiesDrawer",
      description: "Collapsible drawer that wraps NodeProperties and slides in from the right when a node is selected.",
      complex: true
    }
  ]

  def render(assigns) do
    assigns = assign(assigns, :components, @components)

    ~H"""
    <.section_header
      title="Flow Editor Components"
      description="Components that form the visual flow editor at /flows/:id/edit. Components marked as complex require the Drawflow JS library, the flow canvas LiveView, and full socket assigns."
      module="BlackboexWeb.Components.FlowEditor.*"
    />
    <div class="space-y-10">
      <.showcase_block title="Component catalog">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div
            :for={comp <- @components}
            class={[
              "rounded-lg border p-4 space-y-1.5",
              if(comp.complex, do: "bg-muted/30 border-dashed", else: "bg-card")
            ]}
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-sm font-semibold">{comp.name}</span>
              <span
                :if={comp.complex}
                class="text-2xs font-medium uppercase tracking-wider text-muted-foreground bg-muted px-1.5 py-0.5 rounded"
              >
                complex
              </span>
              <span
                :if={!comp.complex}
                class="text-2xs font-medium uppercase tracking-wider text-success-foreground bg-success/10 px-1.5 py-0.5 rounded"
              >
                showcased
              </span>
            </div>
            <p class="text-xs text-muted-foreground">{comp.description}</p>
            <p class="text-2xs font-mono text-muted-foreground/50">{comp.module}</p>
            <p :if={comp.complex} class="text-2xs text-muted-foreground/60 italic">
              NodePalette, NodeProperties, and PropertiesDrawer require the Drawflow JS library and full flow editor context — see /flows/:id/edit
            </p>
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
