defmodule BlackboexWeb.Components.UI.InlineInput do
  @moduledoc """
  Minimal text input for use outside `<.form>` contexts (property panels, inline edits).

  For form-integrated inputs tied to a `Phoenix.HTML.FormField`, use `<.input>`
  (FormField) instead.

  ## Examples

      <.inline_input type="text" value={@name} phx-blur="rename" />
      <.inline_input type="number" value={@count} placeholder="0" />
  """
  use BlackboexWeb.Component

  attr :type, :string,
    values: ~w(text number password email search tel url),
    default: "text"

  attr :value, :any, default: nil
  attr :name, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(autocomplete disabled max maxlength min minlength pattern readonly required step)

  @spec inline_input(map()) :: Phoenix.LiveView.Rendered.t()
  def inline_input(assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      value={@value}
      placeholder={@placeholder}
      class={
        classes([
          "w-full rounded-lg border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50",
          @class
        ])
      }
      {@rest}
    />
    """
  end
end
