defmodule BlackboexWeb.Components.Shared.IconBadge do
  @moduledoc """
  Circular/rounded icon badge — a colored square with a centered icon.

  Replaces the repeated pattern of a `<div>` with flex/size/rounded/bg-*/text-*
  wrapping a single `<.icon>` used as a visual marker in list items, table rows,
  modal template cards, etc.

  ## Examples

      <.icon_badge icon="hero-bolt" color="accent-blue" />
      <.icon_badge icon="hero-arrow-path" color="accent-violet" />
      <.icon_badge icon="hero-squares-2x2" color="primary" size="md" />
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon

  @colors ~w(primary accent-blue accent-violet accent-amber accent-emerald accent-red accent-purple accent-sky accent-teal accent-rose accent-orange accent-cyan)

  attr :icon, :string, required: true
  attr :color, :string, values: @colors, default: "primary"
  attr :size, :string, values: ~w(sm md), default: "sm"
  attr :class, :any, default: nil

  @spec icon_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def icon_badge(assigns) do
    ~H"""
    <div class={classes([wrapper_class(@size), color_class(@color), @class])}>
      <.icon name={@icon} class={icon_class(@size)} />
    </div>
    """
  end

  defp wrapper_class("sm"), do: "flex size-8 shrink-0 items-center justify-center rounded-lg"
  defp wrapper_class("md"), do: "flex size-10 shrink-0 items-center justify-center rounded-lg"

  defp icon_class("sm"), do: "size-4"
  defp icon_class("md"), do: "size-5"

  defp color_class("primary"), do: "bg-primary/10 text-primary"
  defp color_class("accent-blue"), do: "bg-accent-blue/15 text-accent-blue"
  defp color_class("accent-violet"), do: "bg-accent-violet/15 text-accent-violet"
  defp color_class("accent-amber"), do: "bg-accent-amber/15 text-accent-amber"
  defp color_class("accent-emerald"), do: "bg-accent-emerald/15 text-accent-emerald"
  defp color_class("accent-red"), do: "bg-accent-red/15 text-accent-red"
  defp color_class("accent-purple"), do: "bg-accent-purple/15 text-accent-purple"
  defp color_class("accent-sky"), do: "bg-accent-sky/15 text-accent-sky"
  defp color_class("accent-teal"), do: "bg-accent-teal/15 text-accent-teal"
  defp color_class("accent-rose"), do: "bg-accent-rose/15 text-accent-rose"
  defp color_class("accent-orange"), do: "bg-accent-orange/15 text-accent-orange"
  defp color_class("accent-cyan"), do: "bg-accent-cyan/15 text-accent-cyan"
end
