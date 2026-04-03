defmodule BlackboexWeb.Components.Shared.ProgressBar do
  @moduledoc """
  Progress bar component for displaying usage against a limit.

  ## Examples

      <.progress_bar label="API Calls" used={450} limit={1000} percentage={45.0} />
      <.progress_bar label="Storage" used="2.3 GB" limit="Unlimited" percentage={0.0} />
      <.progress_bar label="Errors" used={95} limit={100} percentage={95.0} color="bg-destructive" />
  """
  use BlackboexWeb.Component

  attr :label, :string, required: true
  attr :used, :any, required: true
  attr :limit, :any, required: true
  attr :percentage, :float, default: 0.0
  attr :class, :string, default: nil
  attr :color, :string, default: "bg-primary"

  def progress_bar(assigns) do
    assigns = assign(assigns, :fill_pct, min(assigns.percentage, 100.0))

    ~H"""
    <div class={classes(["space-y-1", @class])}>
      <div class="flex items-center justify-between text-sm">
        <span class="font-medium">{@label}</span>
        <span class="text-muted-foreground">{@used} / {@limit}</span>
      </div>
      <div class="h-2 w-full rounded-full bg-muted overflow-hidden">
        <div
          class={classes(["h-full rounded-full transition-all", @color])}
          style={"width: #{@fill_pct}%"}
        />
      </div>
    </div>
    """
  end
end
