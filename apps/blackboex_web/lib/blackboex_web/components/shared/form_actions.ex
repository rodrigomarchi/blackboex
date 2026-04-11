defmodule BlackboexWeb.Components.Shared.FormActions do
  @moduledoc """
  Button row for form/modal footers and card action bars.

  Replaces `<div class="flex gap-2 [justify-end] [mt-N pt-N]">` wrappers
  around action buttons at the bottom of forms, modals, and cards.

  Not to be confused with `.action_row` (which is a "title + description +
  single trailing action" layout for settings/danger-zone rows).

  ## Examples

      <.form_actions>
        <.button type="button" variant="outline">Cancel</.button>
        <.button type="submit" variant="primary">Save</.button>
      </.form_actions>

      <.form_actions align="between">
        <.button variant="destructive">Delete</.button>
        <.button variant="primary">Save</.button>
      </.form_actions>
  """
  use BlackboexWeb.Component

  attr :align, :string, values: ~w(start center end between), default: "end"

  attr :spacing, :string,
    values: ~w(tight default),
    default: "default",
    doc: "tight → just gap; default → also top padding/margin"

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec form_actions(map()) :: Phoenix.LiveView.Rendered.t()
  def form_actions(assigns) do
    assigns =
      assigns
      |> assign(:align_class, align_class(assigns.align))
      |> assign(:spacing_class, spacing_class(assigns.spacing))

    ~H"""
    <div class={classes(["flex gap-2", @align_class, @spacing_class, @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp align_class("start"), do: "justify-start"
  defp align_class("center"), do: "justify-center"
  defp align_class("end"), do: "justify-end"
  defp align_class("between"), do: "justify-between"

  defp spacing_class("tight"), do: nil
  defp spacing_class("default"), do: "pt-4"
end
