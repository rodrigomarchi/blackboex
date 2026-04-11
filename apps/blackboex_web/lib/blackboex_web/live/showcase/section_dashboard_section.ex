defmodule BlackboexWeb.Showcase.Sections.DashboardSection do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.DashboardSection
  import BlackboexWeb.Components.Shared.StatFigure

  @code_basic ~S"""
  <.dashboard_section icon="hero-chart-bar" title="Request Volume">
    <p class="text-2xl font-bold">48,291</p>
    <p class="text-muted-caption">Total this period</p>
  </.dashboard_section>
  """

  @code_accent ~S"""
  <.dashboard_section icon="hero-sparkles-mini" icon_class="text-accent-violet" title="LLM Calls">
    <.stat_figure label="Total" value="1,204" />
  </.dashboard_section>
  """

  @code_grid ~S"""
  <div class="grid grid-cols-3 gap-4">
    <.dashboard_section icon="hero-cube" icon_class="text-primary" title="APIs">
      <.stat_figure label="Active" value="8" />
    </.dashboard_section>
    <.dashboard_section icon="hero-arrow-path" icon_class="text-accent-teal" title="Flows">
      <.stat_figure label="Running" value="3" />
    </.dashboard_section>
    <.dashboard_section icon="hero-key" icon_class="text-accent-amber" title="API Keys">
      <.stat_figure label="Issued" value="12" />
    </.dashboard_section>
  </div>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_basic, @code_basic)
      |> assign(:code_accent, @code_accent)
      |> assign(:code_grid, @code_grid)

    ~H"""
    <.section_header
      title="Dashboard Section"
      description="Section container for dashboard pages. Renders a titled section with icon header and inner content area."
      module="BlackboexWeb.Components.Shared.DashboardSection"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic Section with Content" code={@code_basic}>
        <.dashboard_section icon="hero-chart-bar" title="Request Volume">
          <p class="text-2xl font-bold">48,291</p>
          <p class="text-muted-caption">Total this period</p>
        </.dashboard_section>
      </.showcase_block>

      <.showcase_block title="With icon_class Accent Color" code={@code_accent}>
        <div class="grid grid-cols-2 gap-4">
          <.dashboard_section
            icon="hero-sparkles-mini"
            icon_class="text-accent-violet"
            title="LLM Calls"
          >
            <.stat_figure label="Total" value="1,204" />
          </.dashboard_section>
          <.dashboard_section icon="hero-bolt" icon_class="text-accent-amber" title="Executions">
            <.stat_figure label="Total" value="892" />
          </.dashboard_section>
        </div>
      </.showcase_block>

      <.showcase_block title="Multiple Sections Stacked" code={@code_grid}>
        <div class="grid grid-cols-3 gap-4">
          <.dashboard_section icon="hero-cube" icon_class="text-primary" title="APIs">
            <.stat_figure label="Active" value="8" />
          </.dashboard_section>
          <.dashboard_section
            icon="hero-arrow-path"
            icon_class="text-accent-teal"
            title="Flows"
          >
            <.stat_figure label="Running" value="3" />
          </.dashboard_section>
          <.dashboard_section
            icon="hero-key"
            icon_class="text-accent-amber"
            title="API Keys"
          >
            <.stat_figure label="Issued" value="12" />
          </.dashboard_section>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
