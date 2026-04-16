defmodule BlackboexWeb.Components.Shared.PlaygroundEditorField do
  @moduledoc """
  Rich code editor component for Playgrounds.

  Uses the `PlaygroundEditor` hook which adds keyboard shortcuts
  (Cmd+Enter to run, Cmd+S to save, Cmd+Shift+F to format),
  debounced real-time code sync, and server-driven code completion.
  """

  use BlackboexWeb.Component

  attr :id, :string, required: true
  attr :value, :any, required: true
  attr :class, :any, default: nil
  attr :max_height, :string, default: "max-h-full"

  attr :height, :string,
    default: nil,
    doc: "fixed pixel/viewport height (e.g. \"240px\", \"100%\")"

  attr :style, :string, default: nil

  @spec playground_editor_field(map()) :: Phoenix.LiveView.Rendered.t()
  def playground_editor_field(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="PlaygroundEditor"
      phx-update="ignore"
      data-language="elixir"
      data-value={@value}
      style={style_attr(@height, @style)}
      class={classes(["rounded-md overflow-hidden border", "[&_.cm-editor]:#{@max_height}", @class])}
    />
    """
  end

  defp style_attr(nil, nil), do: nil
  defp style_attr(nil, style), do: style
  defp style_attr(height, nil), do: "height: #{height};"
  defp style_attr(height, style), do: "height: #{height}; #{style}"
end
