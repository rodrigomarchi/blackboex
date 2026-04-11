defmodule BlackboexWeb.Showcase.Sections.ListRow do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Badge

  def render(assigns) do
    ~H"""
    <.section_header
      title="List Row"
      description="Horizontal list item row with flex justify-between. Supports bordered/unbounded and compact modes."
      module="BlackboexWeb.Components.Shared.ListRow"
    />
    <div class="space-y-10">
      <.showcase_block title="Bordered (default)">
        <div class="space-y-2">
          <.list_row>
            <span class="text-sm">alice@example.com</span>
            <.badge>Owner</.badge>
          </.list_row>
          <.list_row>
            <span class="text-sm">bob@example.com</span>
            <.badge variant="secondary">Member</.badge>
          </.list_row>
        </div>
      </.showcase_block>

      <.showcase_block title="Inside Divided Panel">
        <.panel variant="divided" padding="none">
          <.list_row bordered={false}>
            <span class="text-sm">Created API</span>
            <span class="text-xs text-muted-foreground">2 hours ago</span>
          </.list_row>
          <.list_row bordered={false}>
            <span class="text-sm">Updated settings</span>
            <span class="text-xs text-muted-foreground">1 day ago</span>
          </.list_row>
          <.list_row bordered={false}>
            <span class="text-sm">Invited member</span>
            <span class="text-xs text-muted-foreground">3 days ago</span>
          </.list_row>
        </.panel>
      </.showcase_block>

      <.showcase_block title="Compact">
        <div class="space-y-1">
          <.list_row compact>
            <span class="text-sm">Compact row 1</span>
            <.icon name="hero-chevron-right" class="size-3 text-muted-foreground" />
          </.list_row>
          <.list_row compact>
            <span class="text-sm">Compact row 2</span>
            <.icon name="hero-chevron-right" class="size-3 text-muted-foreground" />
          </.list_row>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
