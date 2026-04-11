defmodule BlackboexWeb.Components.Shared.ListRow do
  @moduledoc """
  Horizontal list item row: flex justify-between with optional border.

  Replaces `<div class="flex items-center justify-between p-2 border rounded">`
  used for member lists, audit log entries, doc link rows, activity rows.

  Pair with `<.panel variant="divided" padding="none">` + `bordered={false}`
  inner rows to get a bordered group of rows separated by dividers.

  ## Examples

      <.list_row :for={member <- @members}>
        <span>{member.email}</span>
        <.badge>{member.role}</.badge>
      </.list_row>

      <.panel variant="divided" padding="none">
        <.list_row :for={log <- @logs} bordered={false}>
          <span>{log.action}</span>
          <span class="text-xs">{log.at}</span>
        </.list_row>
      </.panel>
  """
  use BlackboexWeb.Component

  attr :bordered, :boolean, default: true
  attr :compact, :boolean, default: false, doc: "reduces vertical padding"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec list_row(map()) :: Phoenix.LiveView.Rendered.t()
  def list_row(assigns) do
    ~H"""
    <div
      class={
        classes([
          "flex items-center justify-between",
          @bordered && "rounded border",
          row_padding(@bordered, @compact),
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp row_padding(true, true), do: "p-1.5"
  defp row_padding(true, false), do: "p-2"
  defp row_padding(false, true), do: "py-1.5"
  defp row_padding(false, false), do: "py-2 px-3"
end
