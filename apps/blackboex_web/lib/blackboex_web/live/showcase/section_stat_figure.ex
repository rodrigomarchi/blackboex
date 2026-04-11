defmodule BlackboexWeb.Showcase.Sections.StatFigure do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.StatFigure

  @code_basic ~S"""
  <.stat_figure label="Total Requests" value="12,345" />
  <.stat_figure label="Active APIs" value="8" />
  """

  @code_colors ~S"""
  <.stat_figure label="Running" value="4" />
  <.stat_figure label="Failed" value="2" color="text-status-failed-foreground" />
  <.stat_figure label="Completed" value="97" color="text-status-completed" />
  <.stat_figure label="Warnings" value="7" color="text-accent-amber" />
  """

  @code_grid ~S"""
  <div class="grid grid-cols-3 gap-6">
    <.stat_figure label="Total Requests" value="48,291" />
    <.stat_figure label="Avg Latency" value="38ms" />
    <.stat_figure label="Error Rate" value="0.4%" color="text-status-failed-foreground" />
  </div>
  """

  @code_large ~S"""
  <.stat_figure label="Total Tokens Used" value="1,204,892" />
  <.stat_figure label="Monthly Cost" value="$2,481.50" />
  <.stat_figure label="Uptime" value="99.97%" color="text-status-completed" />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_basic, @code_basic)
      |> assign(:code_colors, @code_colors)
      |> assign(:code_grid, @code_grid)
      |> assign(:code_large, @code_large)

    ~H"""
    <.section_header
      title="Stat Figure"
      description="Large emphasized stat with label below. Use for primary KPI displays where the number should be the visual focus."
      module="BlackboexWeb.Components.Shared.StatFigure"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic" code={@code_basic}>
        <div class="flex gap-8">
          <.stat_figure label="Total Requests" value="12,345" />
          <.stat_figure label="Active APIs" value="8" />
        </div>
      </.showcase_block>

      <.showcase_block title="Color Variants" code={@code_colors}>
        <div class="flex gap-8">
          <.stat_figure label="Running" value="4" />
          <.stat_figure label="Failed" value="2" color="text-status-failed-foreground" />
          <.stat_figure label="Completed" value="97" color="text-status-completed" />
          <.stat_figure label="Warnings" value="7" color="text-accent-amber" />
        </div>
      </.showcase_block>

      <.showcase_block title="Grid of Figures" code={@code_grid}>
        <div class="grid grid-cols-3 gap-6">
          <.stat_figure label="Total Requests" value="48,291" />
          <.stat_figure label="Avg Latency" value="38ms" />
          <.stat_figure label="Error Rate" value="0.4%" color="text-status-failed-foreground" />
        </div>
      </.showcase_block>

      <.showcase_block title="Large Values" code={@code_large}>
        <div class="flex gap-10">
          <.stat_figure label="Total Tokens Used" value="1,204,892" />
          <.stat_figure label="Monthly Cost" value="$2,481.50" />
          <.stat_figure label="Uptime" value="99.97%" color="text-status-completed" />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
