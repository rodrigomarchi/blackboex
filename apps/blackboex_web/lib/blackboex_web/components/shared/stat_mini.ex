defmodule BlackboexWeb.Components.Shared.StatMini do
  @moduledoc "Compact stat box for inline metric grids."
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon

  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :icon, :string, default: nil
  attr :icon_class, :string, default: nil
  attr :size, :string, default: "sm", values: ~w(sm lg)
  attr :label_position, :string, default: "below", values: ~w(above below)
  attr :class, :string, default: nil

  @spec stat_mini(map()) :: Phoenix.LiveView.Rendered.t()
  def stat_mini(assigns) do
    ~H"""
    <div class={classes(["rounded-lg border text-center", padding(@size), @class])}>
      <p
        :if={@label_position == "above"}
        class={classes(["text-muted-caption", @icon && "flex items-center justify-center gap-1"])}
      >
        <.icon :if={@icon} name={@icon} class={classes(["size-3.5", @icon_class])} />
        {@label}
      </p>
      <p class={value_class(@size)}>{@value}</p>
      <p
        :if={@label_position == "below"}
        class={classes(["text-muted-caption", @icon && "flex items-center justify-center gap-1"])}
      >
        <.icon :if={@icon} name={@icon} class={classes(["size-3.5", @icon_class])} />
        {@label}
      </p>
    </div>
    """
  end

  defp padding("sm"), do: "p-3"
  defp padding("lg"), do: "p-4"

  defp value_class("sm"), do: "text-xl font-bold"
  defp value_class("lg"), do: "text-2xl font-bold"
end
