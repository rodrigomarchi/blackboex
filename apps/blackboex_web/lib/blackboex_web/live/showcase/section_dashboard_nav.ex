defmodule BlackboexWeb.Showcase.Sections.DashboardNav do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.DashboardNav

  def render(assigns) do
    ~H"""
    <.section_header
      title="Dashboard Nav"
      description="Tab navigation for the dashboard pages. Renders a horizontal tab bar with icons and links."
      module="BlackboexWeb.Components.Shared.DashboardNav"
    />
    <div class="space-y-10">
      <.showcase_block title="Overview Active">
        <.dashboard_nav active={:overview} base_path="/orgs/demo/dashboard" />
      </.showcase_block>

      <.showcase_block title="APIs Active">
        <.dashboard_nav active={:apis} base_path="/orgs/demo/dashboard" />
      </.showcase_block>

      <.showcase_block title="Usage Active">
        <.dashboard_nav active={:usage} base_path="/orgs/demo/dashboard" />
      </.showcase_block>
    </div>
    """
  end
end
