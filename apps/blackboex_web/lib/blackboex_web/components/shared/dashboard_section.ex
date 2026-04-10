defmodule BlackboexWeb.Components.Shared.DashboardSection do
  @moduledoc """
  Dashboard section: card with an icon+title header and content area.

  Replaces the repeated pattern of `<.card><.card_content class="p-4"><p>label</p>...`
  across all dashboard views.

  ## Examples

      <.dashboard_section icon="hero-sparkles-mini" icon_class="text-accent-violet" title="LLM Calls">
        <.bar_chart data={@data} />
      </.dashboard_section>
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Icon

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :icon_class, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  @spec dashboard_section(map()) :: Phoenix.LiveView.Rendered.t()
  def dashboard_section(assigns) do
    ~H"""
    <.card class={@class} {@rest}>
      <.card_content class="p-4">
        <p class="flex items-center gap-1.5 text-sm font-medium text-muted-foreground mb-3">
          <.icon name={@icon} class={classes(["size-3.5", @icon_class])} />
          {@title}
        </p>
        {render_slot(@inner_block)}
      </.card_content>
    </.card>
    """
  end
end
