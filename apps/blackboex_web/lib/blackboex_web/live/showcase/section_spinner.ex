defmodule BlackboexWeb.Showcase.Sections.Spinner do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Spinner

  def render(assigns) do
    ~H"""
    <.section_header
      title="Spinner"
      description="Animated SVG spinner for loading states. Size controlled via class."
      module="BlackboexWeb.Components.Spinner"
    />
    <div class="space-y-10">
      <.showcase_block title="Sizes">
        <div class="flex items-center gap-6">
          <div class="text-center space-y-2">
            <.spinner class="size-3" />
            <p class="text-xs text-muted-foreground">size-3</p>
          </div>
          <div class="text-center space-y-2">
            <.spinner />
            <p class="text-xs text-muted-foreground">size-4 (default)</p>
          </div>
          <div class="text-center space-y-2">
            <.spinner class="size-6" />
            <p class="text-xs text-muted-foreground">size-6</p>
          </div>
          <div class="text-center space-y-2">
            <.spinner class="size-8" />
            <p class="text-xs text-muted-foreground">size-8</p>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="With Button">
        <.button variant="primary" disabled>
          <.spinner class="size-4" /> Loading...
        </.button>
      </.showcase_block>
    </div>
    """
  end
end
