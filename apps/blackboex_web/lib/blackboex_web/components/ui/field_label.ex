defmodule BlackboexWeb.Components.UI.FieldLabel do
  @moduledoc """
  Compact label with optional leading icon for inline form fields.

  Used in the flow editor property panels and schema builder where form controls
  live outside a `<.form>` context and need a minimal, icon-friendly label.

  ## Examples

      <.field_label>Name</.field_label>
      <.field_label icon="hero-code-bracket" icon_color="text-accent-purple">Code</.field_label>
  """
  use BlackboexWeb.Component

  alias BlackboexWeb.Components.Icon

  attr :icon, :string, default: nil
  attr :icon_color, :string, default: "text-accent-blue"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(for)

  slot :inner_block, required: true

  @spec field_label(map()) :: Phoenix.LiveView.Rendered.t()
  def field_label(assigns) do
    ~H"""
    <label
      class={
        classes([
          "flex items-center gap-1.5 text-xs font-medium text-muted-foreground mb-1.5",
          @class
        ])
      }
      {@rest}
    >
      <Icon.icon :if={@icon} name={@icon} class={classes(["size-3.5", @icon_color])} />
      {render_slot(@inner_block)}
    </label>
    """
  end
end
