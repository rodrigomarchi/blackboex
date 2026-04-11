defmodule BlackboexWeb.Showcase.Sections.Tooltip do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Tooltip

  def render(assigns) do
    ~H"""
    <.section_header
      title="Tooltip"
      description="CSS-only hover tooltip. Wraps any element and shows content on hover. Supports side positioning."
      module="BlackboexWeb.Components.Tooltip"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic Tooltip">
        <div class="flex gap-6">
          <.tooltip>
            <.tooltip_trigger>
              <.button variant="outline">Hover me</.button>
            </.tooltip_trigger>
            <.tooltip_content>Tooltip content appears here</.tooltip_content>
          </.tooltip>
          <.tooltip>
            <.tooltip_trigger>
              <.button variant="ghost" size="icon">
                <.icon name="hero-information-circle" class="size-4" />
              </.button>
            </.tooltip_trigger>
            <.tooltip_content>This icon has additional context</.tooltip_content>
          </.tooltip>
        </div>
      </.showcase_block>

      <.showcase_block title="Side Variants">
        <div class="flex gap-8 justify-center py-8">
          <.tooltip>
            <.tooltip_trigger><.button variant="outline" size="sm">Top</.button></.tooltip_trigger>
            <.tooltip_content side="top">Top tooltip</.tooltip_content>
          </.tooltip>
          <.tooltip>
            <.tooltip_trigger><.button variant="outline" size="sm">Bottom</.button></.tooltip_trigger>
            <.tooltip_content side="bottom">Bottom tooltip</.tooltip_content>
          </.tooltip>
          <.tooltip>
            <.tooltip_trigger><.button variant="outline" size="sm">Left</.button></.tooltip_trigger>
            <.tooltip_content side="left">Left tooltip</.tooltip_content>
          </.tooltip>
          <.tooltip>
            <.tooltip_trigger><.button variant="outline" size="sm">Right</.button></.tooltip_trigger>
            <.tooltip_content side="right">Right tooltip</.tooltip_content>
          </.tooltip>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
