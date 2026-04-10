defmodule BlackboexWeb.Components.FlowEditor.NodePalette do
  @moduledoc """
  Icon-only sidebar with draggable node types for the flow editor canvas.
  """

  use BlackboexWeb, :html

  attr :node_types, :list, required: true

  def node_palette(assigns) do
    ~H"""
    <aside class="flex w-14 shrink-0 flex-col items-center border-r bg-card py-2 gap-1 overflow-y-auto">
      <div
        :for={node <- @node_types}
        draggable="true"
        data-node-type={node.type}
        data-node-label={node.label}
        data-node-inputs={node.inputs}
        data-node-outputs={node.outputs}
        title={node.label}
        class="flex size-9 cursor-grab items-center justify-center rounded-lg border border-transparent hover:border-primary/50 hover:shadow-sm active:cursor-grabbing transition-all"
        style={"color: #{node.color}"}
      >
        <.icon name={node.icon} class="size-5" />
      </div>
    </aside>
    """
  end
end
