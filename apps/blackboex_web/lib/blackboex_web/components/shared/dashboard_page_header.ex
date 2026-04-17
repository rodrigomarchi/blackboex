defmodule BlackboexWeb.Components.Shared.DashboardPageHeader do
  @moduledoc """
  Standard header for dashboard tab views with icon, title, subtitle,
  navigation tabs, and period selector.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Shared.DashboardNav
  import BlackboexWeb.Components.Shared.PeriodSelector

  attr :icon, :string, required: true
  attr :icon_class, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :active_tab, :atom, required: true
  attr :base_path, :string, required: true
  attr :period, :string, required: true

  @spec dashboard_page_header(map()) :: Phoenix.LiveView.Rendered.t()
  def dashboard_page_header(assigns) do
    ~H"""
    <.header>
      <span class="flex items-center gap-2">
        <.icon name={@icon} class={"size-5 #{@icon_class}"} /> {@title}
      </span>
      <:subtitle>{@subtitle}</:subtitle>
      <:actions>
        <div class="flex items-center gap-3">
          <.dashboard_nav active={@active_tab} base_path={@base_path} />
          <.period_selector period={@period} />
        </div>
      </:actions>
    </.header>
    """
  end
end
