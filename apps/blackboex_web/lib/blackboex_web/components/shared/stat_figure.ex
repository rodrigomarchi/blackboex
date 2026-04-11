defmodule BlackboexWeb.Components.Shared.StatFigure do
  @moduledoc """
  Wrapper-less metric value + label pair for use inside cards.

  Unlike `stat_card`, this has no card border/background — it's meant to be
  placed inside an existing `<.card>` or `<.dashboard_section>`.

  ## Examples

      <.stat_figure label="Running" value={@count} />
      <.stat_figure label="Failed" value={@errors} color="text-status-failed-foreground" />
  """
  use BlackboexWeb.Component

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: nil
  attr :class, :any, default: nil

  @spec stat_figure(map()) :: Phoenix.LiveView.Rendered.t()
  def stat_figure(assigns) do
    ~H"""
    <div class={@class}>
      <p class={classes(["text-2xl font-bold", @color])}>{@value}</p>
      <p class="text-muted-caption">{@label}</p>
    </div>
    """
  end
end
