defmodule BlackboexWeb.Components.Shared.DescriptionList do
  @moduledoc """
  Description list component for displaying labeled key-value pairs in a grid.

  ## Examples

      <.description_list>
        <:item label="Status"><.badge>Active</.badge></:item>
        <:item label="Created">Jan 1, 2025</:item>
        <:item label="Owner">alice@example.com</:item>
      </.description_list>
  """
  use BlackboexWeb.Component

  attr :class, :string, default: nil

  slot :item, required: true do
    attr :label, :string, required: true
  end

  def description_list(assigns) do
    ~H"""
    <dl class={classes(["grid grid-cols-1 md:grid-cols-2 gap-4 text-sm", @class])}>
      <div :for={item <- @item}>
        <dt class="font-medium text-muted-foreground">{item.label}</dt>
        <dd class="mt-1">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end
end
