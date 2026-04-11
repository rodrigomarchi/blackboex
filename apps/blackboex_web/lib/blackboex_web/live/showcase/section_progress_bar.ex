defmodule BlackboexWeb.Showcase.Sections.ProgressBar do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.ProgressBar

  def render(assigns) do
    ~H"""
    <.section_header
      title="Progress Bar"
      description="Usage progress bar with label, used/limit display, and fill percentage. Supports custom colors."
      module="BlackboexWeb.Components.Shared.ProgressBar"
    />
    <div class="space-y-10 max-w-xl">
      <.showcase_block title="Basic">
        <div class="space-y-4">
          <.progress_bar label="API Calls" used="450" limit="1,000" percentage={45.0} />
          <.progress_bar label="Storage" used="2.3 GB" limit="5 GB" percentage={46.0} />
        </div>
      </.showcase_block>

      <.showcase_block title="High Usage (Destructive Color)">
        <.progress_bar
          label="Rate Limit"
          used="95"
          limit="100"
          percentage={95.0}
          color="bg-destructive"
        />
      </.showcase_block>

      <.showcase_block title="Full Range">
        <div class="space-y-4">
          <.progress_bar label="Empty" used="0" limit="100" percentage={0.0} />
          <.progress_bar label="Quarter" used="25" limit="100" percentage={25.0} />
          <.progress_bar label="Half" used="50" limit="100" percentage={50.0} />
          <.progress_bar label="Three Quarters" used="75" limit="100" percentage={75.0} />
          <.progress_bar label="Full" used="100" limit="100" percentage={100.0} />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
