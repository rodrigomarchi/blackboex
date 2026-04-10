defmodule BlackboexWeb.Components.UI.InlineTextarea do
  @moduledoc """
  Minimal textarea for use outside `<.form>` contexts (property panels, inline edits).

  For form-integrated textareas tied to a `Phoenix.HTML.FormField`, use
  `<.input type="textarea">` (FormField) instead.

  ## Examples

      <.inline_textarea value={@description} rows="4" phx-blur="update" />
  """
  use BlackboexWeb.Component

  attr :value, :any, default: nil
  attr :name, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :rows, :string, default: "3"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(autocomplete disabled maxlength minlength readonly required)

  @spec inline_textarea(map()) :: Phoenix.LiveView.Rendered.t()
  def inline_textarea(assigns) do
    ~H"""
    <textarea
      name={@name}
      rows={@rows}
      placeholder={@placeholder}
      class={
        classes([
          "w-full rounded-lg border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50",
          @class
        ])
      }
      {@rest}
    >{@value}</textarea>
    """
  end
end
