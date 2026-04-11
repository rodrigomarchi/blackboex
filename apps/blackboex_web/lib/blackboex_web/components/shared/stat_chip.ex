defmodule BlackboexWeb.Components.Shared.StatChip do
  @moduledoc """
  Inline key-value display chip for metadata (duration, node count, etc.).

  ## Examples

      <.stat_chip icon="hero-clock" label="Duration" value="1.2s" />
      <.stat_chip icon="hero-squares-2x2" label="Nodes" value="5" />
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon

  attr :icon, :string, default: nil
  attr :icon_class, :string, default: nil
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :class, :any, default: nil

  @spec stat_chip(map()) :: Phoenix.LiveView.Rendered.t()
  def stat_chip(assigns) do
    ~H"""
    <div class={
      classes([
        "flex items-center gap-1.5 rounded-lg border bg-card px-3 py-1.5 text-muted-foreground",
        @class
      ])
    }>
      <.icon :if={@icon} name={@icon} class={classes(["size-3.5", @icon_class])} />
      <span class="text-xs">{@label}</span>
      <span class="text-xs font-semibold text-foreground">{@value}</span>
    </div>
    """
  end
end
