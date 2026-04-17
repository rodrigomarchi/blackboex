defmodule BlackboexWeb.Showcase.Sections.DashboardPageHeader do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.DashboardPageHeader

  @code_apis ~S"""
  <.dashboard_page_header
    icon="hero-cube"
    icon_class="text-accent-violet"
    title="Dashboard"
    subtitle="Monitor API performance and usage"
    active_tab={:apis}
    base_path="/orgs/demo/dashboard"
    period="7d"
  />
  """

  @code_overview ~S"""
  <.dashboard_page_header
    icon="hero-squares-2x2"
    icon_class="text-primary"
    title="Dashboard"
    subtitle="Overview of all activity"
    active_tab={:overview}
    base_path="/orgs/demo/dashboard"
    period="30d"
  />
  """

  @code_flows ~S"""
  <.dashboard_page_header
    icon="hero-arrow-path"
    icon_class="text-accent-teal"
    title="Flows"
    subtitle="Manage and monitor your automation flows"
    active_tab={:flows}
    base_path="/orgs/demo/dashboard"
    period="24h"
  />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_apis, @code_apis)
      |> assign(:code_overview, @code_overview)
      |> assign(:code_flows, @code_flows)

    ~H"""
    <.section_header
      title="Dashboard Page Header"
      description="Page header for dashboard pages. Shows icon, title, subtitle, period selector, and tab navigation (Overview/APIs/Flows/Usage/LLM)."
      module="BlackboexWeb.Components.Shared.DashboardPageHeader"
    />
    <div class="space-y-10">
      <.showcase_block title="APIs Tab" code={@code_apis}>
        <.dashboard_page_header
          icon="hero-cube"
          icon_class="text-accent-violet"
          title="Dashboard"
          subtitle="Monitor API performance and usage"
          active_tab={:apis}
          base_path="/orgs/demo/dashboard"
          period="7d"
        />
      </.showcase_block>

      <.showcase_block title="Overview Tab" code={@code_overview}>
        <.dashboard_page_header
          icon="hero-squares-2x2"
          icon_class="text-primary"
          title="Dashboard"
          subtitle="Overview of all activity"
          active_tab={:overview}
          base_path="/orgs/demo/dashboard"
          period="30d"
        />
      </.showcase_block>

      <.showcase_block title="Different Icons and Subtitles" code={@code_flows}>
        <.dashboard_page_header
          icon="hero-arrow-path"
          icon_class="text-accent-teal"
          title="Flows"
          subtitle="Manage and monitor your automation flows"
          active_tab={:flows}
          base_path="/orgs/demo/dashboard"
          period="24h"
        />
      </.showcase_block>
    </div>
    """
  end
end
