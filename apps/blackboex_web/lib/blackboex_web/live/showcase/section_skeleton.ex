defmodule BlackboexWeb.Showcase.Sections.Skeleton do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Skeleton

  def render(assigns) do
    ~H"""
    <.section_header
      title="Skeleton"
      description="Pulsing placeholder for loading states. Compose with class for shape and size."
      module="BlackboexWeb.Components.Skeleton"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic Shapes">
        <div class="space-y-4">
          <.skeleton class="h-4 w-48" />
          <.skeleton class="h-4 w-64" />
          <.skeleton class="h-4 w-32" />
        </div>
      </.showcase_block>

      <.showcase_block title="Card Skeleton">
        <div class="rounded-lg border p-4 space-y-3 max-w-sm">
          <.skeleton class="h-5 w-40" />
          <.skeleton class="h-3 w-full" />
          <.skeleton class="h-3 w-3/4" />
          <div class="flex gap-2 pt-2">
            <.skeleton class="h-8 w-20 rounded-md" />
            <.skeleton class="h-8 w-20 rounded-md" />
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Avatar + Lines">
        <div class="flex items-center gap-3">
          <.skeleton class="size-10 rounded-full" />
          <div class="space-y-2">
            <.skeleton class="h-4 w-32" />
            <.skeleton class="h-3 w-24" />
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
