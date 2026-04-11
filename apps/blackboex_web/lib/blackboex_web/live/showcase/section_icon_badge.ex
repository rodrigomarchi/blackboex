defmodule BlackboexWeb.Showcase.Sections.IconBadge do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.IconBadge

  def render(assigns) do
    ~H"""
    <.section_header
      title="Icon Badge"
      description="Circular/rounded icon badge — a colored square with a centered icon. 12 color options and two sizes."
      module="BlackboexWeb.Components.Shared.IconBadge"
    />
    <div class="space-y-10">
      <.showcase_block title="Colors">
        <div class="flex flex-wrap gap-3">
          <.icon_badge icon="hero-bolt" color="primary" />
          <.icon_badge icon="hero-cube" color="accent-blue" />
          <.icon_badge icon="hero-arrow-path" color="accent-violet" />
          <.icon_badge icon="hero-key" color="accent-amber" />
          <.icon_badge icon="hero-check-circle" color="accent-emerald" />
          <.icon_badge icon="hero-x-circle" color="accent-red" />
          <.icon_badge icon="hero-code-bracket" color="accent-purple" />
          <.icon_badge icon="hero-globe-alt" color="accent-sky" />
          <.icon_badge icon="hero-sparkles" color="accent-teal" />
          <.icon_badge icon="hero-heart" color="accent-rose" />
          <.icon_badge icon="hero-fire" color="accent-orange" />
          <.icon_badge icon="hero-beaker" color="accent-cyan" />
        </div>
      </.showcase_block>

      <.showcase_block title="Sizes">
        <div class="flex items-center gap-4">
          <div class="text-center space-y-2">
            <.icon_badge icon="hero-bolt" color="primary" size="sm" />
            <p class="text-xs text-muted-foreground">sm</p>
          </div>
          <div class="text-center space-y-2">
            <.icon_badge icon="hero-bolt" color="primary" size="md" />
            <p class="text-xs text-muted-foreground">md</p>
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
