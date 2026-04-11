defmodule BlackboexWeb.Components.Shared.PeriodSelector do
  @moduledoc """
  Period selector buttons for dashboard views.
  """

  use BlackboexWeb, :html

  @periods [{"24h", "Today"}, {"7d", "7 days"}, {"30d", "30 days"}]

  attr :period, :string, required: true

  @spec period_selector(map()) :: Phoenix.LiveView.Rendered.t()
  def period_selector(assigns) do
    assigns = assign(assigns, :periods, @periods)

    ~H"""
    <div class="flex gap-1">
      <.button
        :for={{value, label} <- @periods}
        phx-click="set_period"
        phx-value-period={value}
        variant={if value == @period, do: "primary", else: "default"}
        size="sm"
      >
        {label}
      </.button>
    </div>
    """
  end
end
