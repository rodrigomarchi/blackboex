defmodule BlackboexWeb.Components.Editor.BottomPanel do
  @moduledoc """
  Bottom panel shell with tab bar for Test, Validation, and Versions.
  Content is provided via the inner_block slot by the parent.
  """
  use BlackboexWeb, :html

  import BlackboexWeb.Components.Shared.UnderlineTabs

  attr :active_tab, :string, default: "test"
  attr :validation_report, :map, default: nil
  slot :inner_block, required: true

  @spec bottom_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def bottom_panel(assigns) do
    ~H"""
    <div class="flex flex-col border-t bg-card" style="height: 35vh; min-height: 200px;">
      <div class="flex items-center border-b px-2 shrink-0">
        <.underline_tabs
          tabs={bottom_tabs(assigns)}
          active={@active_tab}
          click_event="switch_bottom_tab"
          class="flex-1 border-b-0"
        />
        <.button
          variant="ghost-muted"
          size="icon-sm"
          phx-click="toggle_bottom_panel"
          title="Close"
        >
          <.icon name="hero-x-mark" class="size-3.5" />
        </.button>
      </div>

      <div class="flex-1 overflow-auto p-3">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp bottom_tabs(%{validation_report: nil}) do
    [{"test", "Test"}, {"validation", "Validation"}, {"versions", "Versions"}]
  end

  defp bottom_tabs(%{validation_report: report}) do
    badge = if report.overall == :pass, do: "✓", else: "!"
    [{"test", "Test"}, {"validation", "Validation", badge}, {"versions", "Versions"}]
  end
end
