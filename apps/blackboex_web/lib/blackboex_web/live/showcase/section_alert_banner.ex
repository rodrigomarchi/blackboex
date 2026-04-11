defmodule BlackboexWeb.Showcase.Sections.AlertBanner do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.UI.AlertBanner

  def render(assigns) do
    ~H"""
    <.section_header
      title="Alert Banner"
      description="Contextual feedback banner for inline alerts. Six variants with optional leading icon."
      module="BlackboexWeb.Components.UI.AlertBanner"
    />
    <div class="space-y-10">
      <.showcase_block title="All Variants">
        <div class="space-y-3">
          <.alert_banner variant="destructive">Something went wrong.</.alert_banner>
          <.alert_banner variant="warning">This action cannot be undone.</.alert_banner>
          <.alert_banner variant="info">Your API is being provisioned.</.alert_banner>
          <.alert_banner variant="success">Operation completed successfully.</.alert_banner>
          <.alert_banner variant="neutral">Neutral tip without tinted background.</.alert_banner>
          <.alert_banner variant="primary">Highlighted primary-colored banner.</.alert_banner>
        </div>
      </.showcase_block>

      <.showcase_block title="With Icons">
        <div class="space-y-3">
          <.alert_banner variant="destructive" icon="hero-x-circle">
            Deployment failed. Check the logs for details.
          </.alert_banner>
          <.alert_banner variant="warning" icon="hero-exclamation-triangle">
            You are approaching your usage limit.
          </.alert_banner>
          <.alert_banner variant="info" icon="hero-information-circle">
            New features are available in this release.
          </.alert_banner>
          <.alert_banner variant="success" icon="hero-check-circle">
            All tests passed.
          </.alert_banner>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
