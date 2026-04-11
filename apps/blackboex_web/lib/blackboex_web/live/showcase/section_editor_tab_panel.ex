defmodule BlackboexWeb.Showcase.Sections.EditorTabPanel do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  def render(assigns) do
    ~H"""
    <.section_header
      title="Editor Tab Panel"
      description="Scrollable content wrapper for editor tabs. Controls max-width (none, 3xl, 4xl, 5xl), padding (sm, default), and spacing (none, default)."
      module="BlackboexWeb.Components.Shared.EditorTabPanel"
    />
    <div class="space-y-10">
      <.showcase_block title="Default">
        <div class="border rounded-lg h-48 overflow-hidden">
          <.editor_tab_panel>
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Content block 1 (default padding p-6, space-y-6)
            </div>
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Content block 2
            </div>
          </.editor_tab_panel>
        </div>
      </.showcase_block>

      <.showcase_block title="Max Width 3xl + Small Padding">
        <div class="border rounded-lg h-48 overflow-hidden">
          <.editor_tab_panel max_width="3xl" padding="sm">
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Narrow content with max-w-3xl, padding p-4
            </div>
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Second block
            </div>
          </.editor_tab_panel>
        </div>
      </.showcase_block>

      <.showcase_block title="Max Width 4xl">
        <div class="border rounded-lg h-48 overflow-hidden">
          <.editor_tab_panel max_width="4xl">
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Content with max-w-4xl
            </div>
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Second block
            </div>
          </.editor_tab_panel>
        </div>
      </.showcase_block>

      <.showcase_block title="Max Width 5xl">
        <div class="border rounded-lg h-48 overflow-hidden">
          <.editor_tab_panel max_width="5xl">
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Content with max-w-5xl
            </div>
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Second block
            </div>
          </.editor_tab_panel>
        </div>
      </.showcase_block>

      <.showcase_block title="Spacing None">
        <div class="border rounded-lg h-48 overflow-hidden">
          <.editor_tab_panel spacing="none">
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Block 1 (no vertical spacing between children)
            </div>
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Block 2 (directly adjacent)
            </div>
          </.editor_tab_panel>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
