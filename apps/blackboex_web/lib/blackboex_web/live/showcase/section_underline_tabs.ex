defmodule BlackboexWeb.Showcase.Sections.UnderlineTabs do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.UnderlineTabs

  def render(assigns) do
    ~H"""
    <.section_header
      title="Underline Tabs"
      description="Underline-style tab bar for switching between content panels. Supports optional badge on tabs."
      module="BlackboexWeb.Components.Shared.UnderlineTabs"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic">
        <.underline_tabs
          tabs={[{"info", "Info"}, {"code", "Code"}, {"tests", "Tests"}]}
          active="info"
          click_event="noop"
        />
      </.showcase_block>

      <.showcase_block title="With Badge">
        <.underline_tabs
          tabs={[{"info", "Info"}, {"code", "Code"}, {"errors", "Errors", "3"}]}
          active="code"
          click_event="noop"
        />
      </.showcase_block>
    </div>
    """
  end
end
