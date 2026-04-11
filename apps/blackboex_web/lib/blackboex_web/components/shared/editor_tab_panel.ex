defmodule BlackboexWeb.Components.Shared.EditorTabPanel do
  @moduledoc """
  Scrollable content wrapper for an editor tab inside `<.editor_shell>`.

  Replaces `<div class="p-N overflow-y-auto h-full [max-w-NN] space-y-6">`
  wrappers that every `api_live/edit/*` tab reproduces individually.

  Owns: vertical scroll, full height, default vertical rhythm, and optional
  max-width for narrow content tabs (info, publish).

  ## Examples

      <.editor_shell {@assigns} active_tab="info">
        <.editor_tab_panel max_width="3xl" padding="sm">
          <.section_heading>API Information</.section_heading>
          ...
        </.editor_tab_panel>
      </.editor_shell>
  """
  use BlackboexWeb.Component

  attr :max_width, :string, values: ~w(none 3xl 4xl 5xl), default: "none"
  attr :padding, :string, values: ~w(sm default), default: "default"
  attr :spacing, :string, values: ~w(none default), default: "default"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec editor_tab_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def editor_tab_panel(assigns) do
    assigns =
      assigns
      |> assign(:padding_class, padding_class(assigns.padding))
      |> assign(:max_width_class, max_width_class(assigns.max_width))
      |> assign(:spacing_class, spacing_class(assigns.spacing))

    ~H"""
    <div
      class={
        classes([
          "overflow-y-auto h-full",
          @spacing_class,
          @padding_class,
          @max_width_class,
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp spacing_class("none"), do: nil
  defp spacing_class("default"), do: "space-y-6"

  defp padding_class("sm"), do: "p-4"
  defp padding_class("default"), do: "p-6"

  defp max_width_class("none"), do: nil
  defp max_width_class("3xl"), do: "max-w-3xl"
  defp max_width_class("4xl"), do: "max-w-4xl"
  defp max_width_class("5xl"), do: "max-w-5xl"
end
