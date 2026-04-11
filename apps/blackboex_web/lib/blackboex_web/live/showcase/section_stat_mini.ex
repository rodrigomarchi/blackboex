defmodule BlackboexWeb.Showcase.Sections.StatMini do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.StatMini

  def render(assigns) do
    ~H"""
    <.section_header
      title="Stat Mini"
      description="Compact stat box for inline metric grids. Supports vertical/horizontal layout, sizes, and label position."
      module="BlackboexWeb.Components.Shared.StatMini"
    />
    <div class="space-y-10">
      <.showcase_block title="Vertical (default)">
        <div class="grid grid-cols-4 gap-4">
          <.stat_mini value="1,234" label="Calls" />
          <.stat_mini value="42ms" label="Latency" />
          <.stat_mini value="99.7%" label="Uptime" />
          <.stat_mini value="3" label="Errors" />
        </div>
      </.showcase_block>

      <.showcase_block title="Large Size">
        <div class="grid grid-cols-3 gap-4">
          <.stat_mini value="8" label="Total APIs" size="lg" />
          <.stat_mini value="3" label="Active Flows" size="lg" />
          <.stat_mini value="12" label="API Keys" size="lg" />
        </div>
      </.showcase_block>

      <.showcase_block title="Label Above">
        <div class="grid grid-cols-3 gap-4">
          <.stat_mini value="450" label="Requests" label_position="above" />
          <.stat_mini value="12" label="Errors" label_position="above" />
          <.stat_mini value="38ms" label="P95" label_position="above" />
        </div>
      </.showcase_block>

      <.showcase_block title="Horizontal Layout">
        <div class="grid grid-cols-2 gap-4">
          <.stat_mini value="1,234" label="Total Calls" layout="horizontal" icon="hero-chart-bar" />
          <.stat_mini value="42ms" label="Avg Latency" layout="horizontal" icon="hero-clock" />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
