defmodule BlackboexWeb.Showcase.Sections.PeriodSelector do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.PeriodSelector

  @code_24h ~S"""
  <.period_selector period="24h" />
  """

  @code_7d ~S"""
  <.period_selector period="7d" />
  """

  @code_30d ~S"""
  <.period_selector period="30d" />
  """

  @code_usage ~S"""
  # In the LiveView module:
  def handle_event("set_period", %{"period" => period}, socket) do
    {:noreply, assign(socket, period: period)}
  end

  # In the template:
  <.period_selector period={@period} />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_24h, @code_24h)
      |> assign(:code_7d, @code_7d)
      |> assign(:code_30d, @code_30d)
      |> assign(:code_usage, @code_usage)

    ~H"""
    <.section_header
      title="Period Selector"
      description="Period selector for time-range filtering. Shows predefined period options (24h, 7d, 30d); triggers a phx-click event on selection."
      module="BlackboexWeb.Components.Shared.PeriodSelector"
    />
    <div class="space-y-10">
      <.showcase_block title="24h active" code={@code_24h}>
        <.period_selector period="24h" />
      </.showcase_block>

      <.showcase_block title="7d active" code={@code_7d}>
        <.period_selector period="7d" />
      </.showcase_block>

      <.showcase_block title="30d active" code={@code_30d}>
        <.period_selector period="30d" />
      </.showcase_block>

      <.showcase_block title="Usage Pattern (LiveView)" code={@code_usage}>
        <.panel class="p-4">
          <p class="text-sm text-muted-foreground">
            The component emits
            <code class="text-xs bg-muted px-1 py-0.5 rounded">phx-click="set_period"</code>
            with <code class="text-xs bg-muted px-1 py-0.5 rounded">phx-value-period</code>
            set to the selected value. Handle it in your LiveView with
            <code class="text-xs bg-muted px-1 py-0.5 rounded">handle_event("set_period", params, socket)</code>.
          </p>
        </.panel>
      </.showcase_block>
    </div>
    """
  end
end
