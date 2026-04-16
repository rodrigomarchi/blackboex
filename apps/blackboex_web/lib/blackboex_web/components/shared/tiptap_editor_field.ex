defmodule BlackboexWeb.Components.Shared.TiptapEditorField do
  @moduledoc """
  Wraps the TiptapEditor JS hook in a Phoenix component.

  Renders a `<div phx-hook="TiptapEditor" phx-update="ignore">` that the
  hook turns into a WYSIWYG block editor with slash commands and bubble menu.
  """

  use BlackboexWeb.Component

  @spec tiptap_editor_field(map()) :: Phoenix.LiveView.Rendered.t()

  attr :id, :string, required: true
  attr :value, :string, default: ""
  attr :readonly, :boolean, default: false
  attr :event, :string, default: nil
  attr :field, :string, default: nil
  attr :class, :any, default: nil
  attr :placeholder, :string, default: "Type '/' for commands..."

  def tiptap_editor_field(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="TiptapEditor"
      phx-update="ignore"
      data-value={@value}
      data-readonly={to_string(@readonly)}
      data-event={@event}
      data-field={@field}
      data-placeholder={@placeholder}
      class={classes(["tiptap-container", @class])}
    />
    """
  end
end
