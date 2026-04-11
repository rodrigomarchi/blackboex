defmodule BlackboexWeb.Components.Editor.CodeLabel do
  @moduledoc """
  Micro-label for code block language/type indicators.

  ## Examples

      <.code_label>elixir</.code_label>
      <.code_label variant="dark">json</.code_label>
  """
  use BlackboexWeb.Component

  @variants %{
    "default" => "text-muted-foreground",
    "dark" => "text-white/50"
  }

  attr :variant, :string, values: ~w(default dark), default: "default"
  attr :class, :any, default: nil

  slot :inner_block, required: true

  @spec code_label(map()) :: Phoenix.LiveView.Rendered.t()
  def code_label(assigns) do
    assigns = assign(assigns, :variant_class, @variants[assigns.variant])

    ~H"""
    <span class={classes(["text-2xs font-medium uppercase tracking-wider", @variant_class, @class])}>
      {render_slot(@inner_block)}
    </span>
    """
  end
end
