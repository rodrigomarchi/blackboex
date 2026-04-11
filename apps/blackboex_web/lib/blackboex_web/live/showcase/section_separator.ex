defmodule BlackboexWeb.Showcase.Sections.Separator do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Separator

  def render(assigns) do
    ~H"""
    <.section_header
      title="Separator"
      description="Visual divider line. Supports horizontal and vertical orientations."
      module="BlackboexWeb.Components.Separator"
    />
    <div class="space-y-10">
      <.showcase_block title="Horizontal (default)">
        <div class="space-y-4">
          <p class="text-sm">Content above</p>
          <.separator />
          <p class="text-sm">Content below</p>
        </div>
      </.showcase_block>

      <.showcase_block title="Vertical">
        <div class="flex items-center gap-4 h-8">
          <span class="text-sm">Left</span>
          <.separator orientation="vertical" />
          <span class="text-sm">Right</span>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
