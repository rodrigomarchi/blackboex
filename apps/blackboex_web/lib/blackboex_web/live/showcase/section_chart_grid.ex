defmodule BlackboexWeb.Showcase.Sections.ChartGrid do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  def render(assigns) do
    ~H"""
    <.section_header
      title="Chart Grid"
      description="Responsive grid for chart/dashboard sections. Two or three columns on lg+ screens."
      module="BlackboexWeb.Components.Shared.ChartGrid"
    />
    <div class="space-y-10">
      <.showcase_block title="2 Columns (default)">
        <.chart_grid>
          <.panel>
            <p class="text-sm text-muted-foreground">Chart area 1</p>
            <div class="h-24 rounded bg-muted/30 mt-2" />
          </.panel>
          <.panel>
            <p class="text-sm text-muted-foreground">Chart area 2</p>
            <div class="h-24 rounded bg-muted/30 mt-2" />
          </.panel>
        </.chart_grid>
      </.showcase_block>

      <.showcase_block title="3 Columns">
        <.chart_grid cols="3">
          <.panel>
            <p class="text-sm text-muted-foreground">Chart 1</p>
            <div class="h-20 rounded bg-muted/30 mt-2" />
          </.panel>
          <.panel>
            <p class="text-sm text-muted-foreground">Chart 2</p>
            <div class="h-20 rounded bg-muted/30 mt-2" />
          </.panel>
          <.panel>
            <p class="text-sm text-muted-foreground">Chart 3</p>
            <div class="h-20 rounded bg-muted/30 mt-2" />
          </.panel>
        </.chart_grid>
      </.showcase_block>
    </div>
    """
  end
end
