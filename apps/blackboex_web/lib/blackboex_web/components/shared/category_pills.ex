defmodule BlackboexWeb.Components.Shared.CategoryPills do
  @moduledoc """
  Row of filter pills used in create modals to switch between template categories.
  """
  use BlackboexWeb, :html

  attr :categories, :list, required: true, doc: "list of {category, templates} tuples"
  attr :active, :string, default: nil
  attr :click_event, :string, default: "set_active_category"
  attr :class, :string, default: nil

  @spec category_pills(map()) :: Phoenix.LiveView.Rendered.t()
  def category_pills(assigns) do
    ~H"""
    <div class={["flex gap-1 flex-wrap", @class]}>
      <.button
        :for={{cat, _templates} <- @categories}
        type="button"
        variant="ghost"
        phx-click={@click_event}
        phx-value-category={cat}
        class={[
          "h-auto w-auto rounded-full px-3 py-1 text-xs font-medium transition-colors border hover:bg-transparent",
          if(@active == cat,
            do: "bg-primary text-primary-foreground border-primary",
            else:
              "bg-background text-muted-foreground border-border hover:border-primary/50 hover:text-foreground"
          )
        ]}
      >
        {cat}
      </.button>
    </div>
    """
  end
end
