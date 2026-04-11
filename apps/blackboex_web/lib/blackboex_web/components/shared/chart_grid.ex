defmodule BlackboexWeb.Components.Shared.ChartGrid do
  @moduledoc """
  Two-column responsive grid for chart/dashboard sections on lg+ screens.

  Replaces `<div class="grid gap-4 lg:grid-cols-2">` used to place charts
  side-by-side on desktop.

  ## Examples

      <.chart_grid>
        <.dashboard_section title="Calls">...</.dashboard_section>
        <.dashboard_section title="Errors">...</.dashboard_section>
      </.chart_grid>
  """
  use BlackboexWeb.Component

  attr :cols, :string, values: ~w(2 3), default: "2"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec chart_grid(map()) :: Phoenix.LiveView.Rendered.t()
  def chart_grid(assigns) do
    assigns = assign(assigns, :cols_class, cols_class(assigns.cols))

    ~H"""
    <div class={classes(["grid gap-4", @cols_class, @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp cols_class("2"), do: "lg:grid-cols-2"
  defp cols_class("3"), do: "lg:grid-cols-3"
end
