defmodule BlackboexWeb.Showcase.Sections.EmptyState do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  def render(assigns) do
    ~H"""
    <.section_header
      title="Empty State"
      description="Placeholder for empty lists/pages with icon, title, description, and action slot. Has a compact inline variant. Supports icon_class for custom icon colors."
      module="BlackboexWeb.Components.Shared.EmptyState"
    />
    <div class="space-y-10">
      <.showcase_block title="Full (default)">
        <.empty_state
          icon="hero-inbox"
          title="No APIs yet"
          description="Create your first API to get started."
        >
          <:actions>
            <.button variant="primary">New API</.button>
          </:actions>
        </.empty_state>
      </.showcase_block>

      <.showcase_block title="Without Icon">
        <.empty_state title="No results found" description="Try adjusting your search or filters." />
      </.showcase_block>

      <.showcase_block title="Compact">
        <.empty_state compact title="No items to display" description="Add items to see them here." />
      </.showcase_block>

      <.showcase_block title="Custom icon_class">
        <div class="grid grid-cols-2 gap-4">
          <.empty_state
            icon="hero-exclamation-triangle"
            icon_class="text-accent-amber"
            title="Warning state"
            description="Custom amber icon color via icon_class."
          />
          <.empty_state
            icon="hero-shield-check"
            icon_class="text-status-completed"
            title="Secure"
            description="Custom green icon color via icon_class."
          />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
