defmodule BlackboexWeb.Showcase.Helpers do
  @moduledoc "Shared helpers for showcase section pages."
  use BlackboexWeb, :html

  import BlackboexWeb.Components.Editor.CodeViewer

  @doc """
  Renders a demo block: title + live demo area + optional code example with syntax highlighting.
  The code= attribute should be a HEEx string using ~S to avoid interpolation.
  """
  attr :title, :string, required: true
  attr :code, :string, default: nil
  slot :inner_block, required: true

  def showcase_block(assigns) do
    ~H"""
    <div class="space-y-2">
      <h3 class="text-xs font-semibold text-muted-foreground uppercase tracking-wider">{@title}</h3>
      <div class="rounded-lg border bg-card p-6">
        {render_slot(@inner_block)}
      </div>
      <div :if={@code} class="rounded-lg overflow-hidden border">
        <.code_viewer code={@code} label="HEEx" />
      </div>
    </div>
    """
  end

  @doc "Page header: component name, description, module path."
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :module, :string, default: nil

  def section_header(assigns) do
    ~H"""
    <div class="pb-8 mb-8 border-b space-y-2">
      <h1 class="text-2xl font-bold">{@title}</h1>
      <p class="text-sm text-muted-foreground max-w-2xl">{@description}</p>
      <p :if={@module} class="text-xs font-mono text-muted-foreground/50">{@module}</p>
    </div>
    """
  end
end
