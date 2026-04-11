defmodule BlackboexWeb.Showcase.Sections.IconShowcase do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  def render(assigns) do
    ~H"""
    <.section_header
      title="Icon"
      description="Heroicons integration via the icon component. Pass any hero-* name."
      module="BlackboexWeb.Components.Icon"
    />
    <div class="space-y-10">
      <.showcase_block title="Sizes">
        <div class="flex items-end gap-6">
          <div class="text-center space-y-2">
            <.icon name="hero-bolt" class="size-3" />
            <p class="text-xs text-muted-foreground">size-3</p>
          </div>
          <div class="text-center space-y-2">
            <.icon name="hero-bolt" class="size-4" />
            <p class="text-xs text-muted-foreground">size-4</p>
          </div>
          <div class="text-center space-y-2">
            <.icon name="hero-bolt" class="size-5" />
            <p class="text-xs text-muted-foreground">size-5</p>
          </div>
          <div class="text-center space-y-2">
            <.icon name="hero-bolt" class="size-6" />
            <p class="text-xs text-muted-foreground">size-6</p>
          </div>
          <div class="text-center space-y-2">
            <.icon name="hero-bolt" class="size-8" />
            <p class="text-xs text-muted-foreground">size-8</p>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Common Icons">
        <div class="flex flex-wrap gap-4">
          <div
            :for={
              name <-
                ~w(hero-home hero-cog-6-tooth hero-plus hero-pencil hero-trash hero-eye hero-arrow-path hero-bolt hero-cube hero-key hero-chart-bar hero-sparkles hero-globe-alt hero-document hero-check-circle hero-x-circle hero-exclamation-triangle hero-information-circle)
            }
            class="flex flex-col items-center gap-1 p-2 rounded border w-20"
          >
            <.icon name={name} class="size-5" />
            <span class="text-2xs text-muted-foreground truncate w-full text-center">
              {String.replace(name, "hero-", "")}
            </span>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Colors">
        <div class="flex items-center gap-4">
          <.icon name="hero-check-circle" class="size-5 text-success" />
          <.icon name="hero-x-circle" class="size-5 text-destructive" />
          <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
          <.icon name="hero-information-circle" class="size-5 text-info" />
          <.icon name="hero-sparkles" class="size-5 text-primary" />
          <.icon name="hero-bolt" class="size-5 text-accent-amber" />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
