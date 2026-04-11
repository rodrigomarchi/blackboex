defmodule BlackboexWeb.Components.Shared.Page do
  @moduledoc """
  Layout primitives for normal content pages.

  `.page/1` is the root wrapper — owns page-level vertical spacing. Replaces
  the ad-hoc `<div class="space-y-6">` previously repeated across LiveViews.
  Max-width and horizontal padding live in `BlackboexWeb.Layouts.app` and must
  NOT be re-defined here.

  `.page_section/1` is a lightweight grouping element for subsections inside a
  page, with a `spacing` variant (`tight`, `default`, `loose`).

  ## Example

      <.page>
        <.header>...</.header>
        <.page_section>
          <.card>...</.card>
          <.card>...</.card>
        </.page_section>
      </.page>
  """
  use BlackboexWeb.Component

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec page(map()) :: Phoenix.LiveView.Rendered.t()
  def page(assigns) do
    ~H"""
    <div class={classes(["space-y-6", @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :spacing, :string, values: ~w(tight default loose), default: "default"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec page_section(map()) :: Phoenix.LiveView.Rendered.t()
  def page_section(assigns) do
    ~H"""
    <section class={classes([spacing_class(@spacing), @class])} {@rest}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp spacing_class("tight"), do: "space-y-3"
  defp spacing_class("default"), do: "space-y-4"
  defp spacing_class("loose"), do: "space-y-6"
end
