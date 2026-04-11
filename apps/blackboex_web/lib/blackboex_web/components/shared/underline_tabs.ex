defmodule BlackboexWeb.Components.Shared.UnderlineTabs do
  @moduledoc "Underline-style tab bar for switching between content panels."
  use BlackboexWeb.Component

  attr :tabs, :list,
    required: true,
    doc: "List of {id, label} tuples or {id, label, badge} triples"

  attr :active, :string, required: true
  attr :click_event, :string, required: true
  attr :class, :string, default: nil

  @spec underline_tabs(map()) :: Phoenix.LiveView.Rendered.t()
  def underline_tabs(assigns) do
    ~H"""
    <div class={classes(["flex border-b", @class])}>
      <button
        :for={tab <- @tabs}
        type="button"
        phx-click={@click_event}
        phx-value-tab={tab_id(tab)}
        class={
          classes([
            "flex-1 px-3 py-2 text-xs font-medium border-b-2 transition-colors hover:bg-transparent",
            if(tab_id(tab) == @active,
              do: "border-primary text-primary",
              else: "border-transparent text-muted-foreground hover:text-foreground"
            )
          ])
        }
      >
        {tab_label(tab)}
        <span
          :if={tab_badge(tab)}
          class="ml-1.5 inline-flex items-center rounded-full bg-destructive/10 px-1.5 text-2xs text-destructive"
        >
          {tab_badge(tab)}
        </span>
      </button>
    </div>
    """
  end

  defp tab_id({id, _label}), do: id
  defp tab_id({id, _label, _badge}), do: id

  defp tab_label({_id, label}), do: label
  defp tab_label({_id, label, _badge}), do: label

  defp tab_badge({_id, _label}), do: nil
  defp tab_badge({_id, _label, badge}), do: badge
end
