defmodule BlackboexWeb.Components.Editor.BottomPanel do
  @moduledoc """
  Bottom panel shell with tab bar for Test, Validation, and Versions.
  Content is provided via the inner_block slot by the parent.
  """
  use BlackboexWeb, :html

  import BlackboexWeb.Components.Badge

  attr :active_tab, :string, default: "test"
  attr :validation_report, :map, default: nil
  slot :inner_block, required: true

  @spec bottom_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def bottom_panel(assigns) do
    ~H"""
    <div class="flex flex-col border-t bg-card" style="height: 35vh; min-height: 200px;">
      <div class="flex items-center border-b px-2 shrink-0">
        <.button
          :for={tab <- ~w(test validation versions)}
          variant="ghost"
          phx-click="switch_bottom_tab"
          phx-value-tab={tab}
          class={[
            "h-auto rounded-none px-3 py-1.5 text-xs font-medium border-b-2 transition-colors hover:bg-transparent",
            if(tab == @active_tab,
              do: "border-primary text-primary",
              else: "border-transparent text-muted-foreground hover:text-foreground"
            )
          ]}
        >
          {bottom_tab_label(tab)}
          <.badge
            :if={tab == "validation" && @validation_report != nil}
            size="xs"
            variant="status"
            class={
              "ml-1 " <>
                if(@validation_report.overall == :pass,
                  do: "bg-success/10 text-success-foreground",
                  else: "bg-destructive/10 text-destructive"
                )
            }
          >
            {if @validation_report.overall == :pass, do: "✓", else: "!"}
          </.badge>
        </.button>

        <div class="flex-1" />

        <.button
          variant="ghost"
          size="icon-sm"
          phx-click="toggle_bottom_panel"
          class="text-muted-foreground hover:text-foreground hover:bg-accent"
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

  defp bottom_tab_label("test"), do: "Test"
  defp bottom_tab_label("validation"), do: "Validation"
  defp bottom_tab_label("versions"), do: "Versions"
end
