defmodule BlackboexWeb.Components.Shared.StatCard do
  @moduledoc """
  Stat card component for displaying a labeled metric value.

  ## Examples

      <.stat_card label="Total Requests" value="12,345" />
      <.stat_card label="Error Rate" value="5.2%" color="destructive" />
  """
  use BlackboexWeb.Component

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: nil
  attr :class, :string, default: nil

  def stat_card(assigns) do
    ~H"""
    <div class={classes(["rounded-lg border bg-card p-4 shadow-sm", @class])}>
      <p class="text-xs font-medium text-muted-foreground uppercase tracking-wide">{@label}</p>
      <p class={classes(["mt-1 text-2xl font-bold", @color == "destructive" && "text-destructive"])}>
        {@value}
      </p>
    </div>
    """
  end
end
