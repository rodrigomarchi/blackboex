defmodule BlackboexWeb.Showcase.Sections.StatGrid do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.StatCard

  def render(assigns) do
    ~H"""
    <.section_header
      title="Stat Grid"
      description="Responsive grid wrapper for stat cards. Configurable columns (2-5) and gap sizes (3, 4, 6)."
      module="BlackboexWeb.Components.Shared.StatGrid"
    />
    <div class="space-y-10">
      <.showcase_block title="4 Columns (default)">
        <.stat_grid>
          <.stat_card label="Calls" value="1.2k" />
          <.stat_card label="Errors" value="3" />
          <.stat_card label="Latency" value="42ms" />
          <.stat_card label="Success" value="99.7%" />
        </.stat_grid>
      </.showcase_block>

      <.showcase_block title="3 Columns">
        <.stat_grid cols="3">
          <.stat_card label="APIs" value="8" />
          <.stat_card label="Flows" value="3" />
          <.stat_card label="Keys" value="12" />
        </.stat_grid>
      </.showcase_block>

      <.showcase_block title="5 Columns">
        <.stat_grid cols="5">
          <.stat_card label="APIs" value="8" />
          <.stat_card label="Flows" value="3" />
          <.stat_card label="Keys" value="12" />
          <.stat_card label="Calls" value="45k" />
          <.stat_card label="Errors" value="0" />
        </.stat_grid>
      </.showcase_block>

      <.showcase_block title="2 Columns, Gap 6">
        <.stat_grid cols="2" gap="6">
          <.stat_card label="This Month" value="45,678" />
          <.stat_card label="Last Month" value="38,901" />
        </.stat_grid>
      </.showcase_block>

      <.showcase_block title="Gap 3 (tighter)">
        <.stat_grid cols="4" gap="3">
          <.stat_card label="Calls" value="1.2k" />
          <.stat_card label="Errors" value="3" />
          <.stat_card label="Latency" value="42ms" />
          <.stat_card label="Success" value="99.7%" />
        </.stat_grid>
      </.showcase_block>
    </div>
    """
  end
end
