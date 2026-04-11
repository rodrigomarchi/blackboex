defmodule BlackboexWeb.Components.Shared.Panel do
  @moduledoc """
  Lightweight, flat panel used for internal layout sections. Deliberately
  visually distinct from `.card`:

  * `.card` — rounded-xl, shadow, for top-level containers (settings, billing
    plan cards, feature cards).
  * `.panel` — rounded-lg, no shadow, for compact internal groupings inside an
    editor tab, dashboard section, or publish tab (status header, chart
    container, version entry, link row).

  Replaces hand-written `<div class="rounded-lg border p-4 …">` patterns.

  ## Variants

  * `default` — `rounded-lg border bg-card`
  * `dashed` — dashed border, used for empty-like placeholders
  * `muted` — softer background tint
  * `highlighted` — success-tinted border/background (published version marker)
  * `divided` — for list containers; pairs with `padding="none"` and inner
    rows using `.list_row bordered={false}`

  ## Padding

  * `none` — no padding (use with `divided` or when the inner content manages it)
  * `sm` — `p-3`
  * `default` — `p-4`
  * `lg` — `p-8`
  """
  use BlackboexWeb.Component

  attr :variant, :string,
    values: ~w(default dashed muted highlighted divided),
    default: "default"

  attr :padding, :string, values: ~w(none sm default lg), default: "default"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec panel(map()) :: Phoenix.LiveView.Rendered.t()
  def panel(assigns) do
    assigns =
      assigns
      |> assign(:variant_class, variant_class(assigns.variant))
      |> assign(:padding_class, padding_class(assigns.padding))

    ~H"""
    <div class={classes([@variant_class, @padding_class, @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp variant_class("default"), do: "rounded-lg border bg-card"
  defp variant_class("dashed"), do: "rounded-lg border border-dashed bg-card"
  defp variant_class("muted"), do: "rounded-lg border bg-muted/20"
  defp variant_class("highlighted"), do: "rounded-lg border-success bg-success/5"
  defp variant_class("divided"), do: "rounded-lg border divide-y bg-card"

  defp padding_class("none"), do: nil
  defp padding_class("sm"), do: "p-3"
  defp padding_class("default"), do: "p-4"
  defp padding_class("lg"), do: "p-8"
end
