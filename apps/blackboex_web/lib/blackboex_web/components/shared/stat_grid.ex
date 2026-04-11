defmodule BlackboexWeb.Components.Shared.StatGrid do
  @moduledoc """
  Responsive grid for rows of stat cards.

  Replaces the repeated `<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-N">`
  pattern across dashboards, editor metrics tabs, and key detail pages.

  ## Examples

      <.stat_grid cols="4">
        <.stat_card label="Calls" value="1.2k" />
        <.stat_card label="Errors" value="3" />
        <.stat_card label="Latency" value="42ms" />
        <.stat_card label="Success" value="99.7%" />
      </.stat_grid>
  """
  use BlackboexWeb.Component

  attr :cols, :string,
    values: ~w(2 3 4 5),
    default: "4",
    doc: "max columns at lg breakpoint (always 1 on mobile, 2 at sm)"

  attr :gap, :string, values: ~w(3 4 6), default: "4"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec stat_grid(map()) :: Phoenix.LiveView.Rendered.t()
  def stat_grid(assigns) do
    assigns =
      assigns
      |> assign(:cols_class, cols_class(assigns.cols))
      |> assign(:gap_class, gap_class(assigns.gap))

    ~H"""
    <div class={classes(["grid sm:grid-cols-2", @gap_class, @cols_class, @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp cols_class("2"), do: nil
  defp cols_class("3"), do: "lg:grid-cols-3"
  defp cols_class("4"), do: "lg:grid-cols-4"
  defp cols_class("5"), do: "lg:grid-cols-5"

  defp gap_class("3"), do: "gap-3"
  defp gap_class("4"), do: "gap-4"
  defp gap_class("6"), do: "gap-6"
end
