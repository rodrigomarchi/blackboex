defmodule BlackboexWeb.Components.Shared.CodeEditorField do
  @moduledoc """
  Wrapper component for the CodeMirror-based code editor hook.

  Replaces the repeated `phx-hook="CodeEditor"` div pattern used across
  the application for displaying and editing code/JSON.

  ## Examples

      <.code_editor_field id="my-editor" value={@json_value} />
      <.code_editor_field id="code-editor" value={@code} language="elixir" readonly={false} event="update_code" />
  """

  use BlackboexWeb.Component

  attr :id, :string, required: true
  attr :value, :any, required: true
  attr :language, :string, default: "json"
  attr :readonly, :boolean, default: true
  attr :minimal, :boolean, default: true
  attr :max_height, :string, default: "max-h-96"
  attr :event, :string, default: nil
  attr :field, :string, default: nil
  attr :class, :any, default: nil
  attr :style, :string, default: nil

  @spec code_editor_field(map()) :: Phoenix.LiveView.Rendered.t()
  def code_editor_field(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="CodeEditor"
      phx-update="ignore"
      data-language={@language}
      data-readonly={to_string(@readonly)}
      data-minimal={to_string(@minimal)}
      data-value={@value}
      data-event={@event}
      data-field={@field}
      style={@style}
      class={classes(["rounded-md overflow-hidden border", "[&_.cm-editor]:#{@max_height}", @class])}
    />
    """
  end
end
