defmodule BlackboexWeb.Showcase.Sections.PanelShowcase do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  def render(assigns) do
    ~H"""
    <.section_header
      title="Panel"
      description="Lightweight flat panel for internal layout sections. Five variants and four padding options."
      module="BlackboexWeb.Components.Shared.Panel"
    />
    <div class="space-y-10">
      <.showcase_block title="Variants">
        <div class="space-y-4">
          <.panel>
            <p class="text-sm">Default panel — rounded-lg border bg-card</p>
          </.panel>
          <.panel variant="dashed">
            <p class="text-sm">Dashed — placeholder style</p>
          </.panel>
          <.panel variant="muted">
            <p class="text-sm">Muted — softer background tint</p>
          </.panel>
          <.panel variant="highlighted">
            <p class="text-sm">Highlighted — success-tinted (published version marker)</p>
          </.panel>
          <.panel variant="divided" padding="none">
            <div class="px-4 py-2">Row 1</div>
            <div class="px-4 py-2">Row 2</div>
            <div class="px-4 py-2">Row 3</div>
          </.panel>
        </div>
      </.showcase_block>

      <.showcase_block title="Padding">
        <div class="space-y-4">
          <.panel padding="none">
            <p class="text-sm">padding="none"</p>
          </.panel>
          <.panel padding="sm">
            <p class="text-sm">padding="sm" (p-3)</p>
          </.panel>
          <.panel>
            <p class="text-sm">padding="default" (p-4)</p>
          </.panel>
          <.panel padding="lg">
            <p class="text-sm">padding="lg" (p-8)</p>
          </.panel>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
