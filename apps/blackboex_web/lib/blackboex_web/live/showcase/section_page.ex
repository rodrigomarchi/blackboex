defmodule BlackboexWeb.Showcase.Sections.PageShowcase do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  def render(assigns) do
    ~H"""
    <.section_header
      title="Page"
      description="Layout primitives: page (root vertical spacing) and page_section (subsection grouping with tight/default/loose spacing)."
      module="BlackboexWeb.Components.Shared.Page"
    />
    <div class="space-y-10">
      <.showcase_block title="Page + Page Sections">
        <div class="rounded-lg border p-4 bg-muted/10">
          <.page>
            <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
              Header area (space-y-6 between children)
            </div>
            <.page_section>
              <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
                Section child 1 (space-y-4 default)
              </div>
              <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
                Section child 2
              </div>
            </.page_section>
            <.page_section spacing="tight">
              <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
                Tight section child 1 (space-y-3)
              </div>
              <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
                Tight section child 2
              </div>
            </.page_section>
            <.page_section spacing="loose">
              <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
                Loose section child 1 (space-y-6)
              </div>
              <div class="rounded border border-dashed p-3 text-sm text-muted-foreground">
                Loose section child 2
              </div>
            </.page_section>
          </.page>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
