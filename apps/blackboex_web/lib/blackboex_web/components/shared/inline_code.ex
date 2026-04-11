defmodule BlackboexWeb.Components.Shared.InlineCode do
  @moduledoc "Inline code display component for code snippets and tokens."

  use BlackboexWeb.Component

  attr :variant, :string, values: ~w(default block), default: "default"
  attr :class, :string, default: nil

  slot :inner_block, required: true

  @spec inline_code(map()) :: Phoenix.LiveView.Rendered.t()
  def inline_code(assigns) do
    ~H"""
    <code class={classes([variant_class(@variant), @class])}>
      {render_slot(@inner_block)}
    </code>
    """
  end

  defp variant_class("default"), do: "rounded bg-muted px-1.5 py-0.5 text-xs font-mono"

  defp variant_class("block"),
    do:
      "block bg-accent text-accent-foreground p-2 rounded font-mono text-sm break-all select-all"
end
