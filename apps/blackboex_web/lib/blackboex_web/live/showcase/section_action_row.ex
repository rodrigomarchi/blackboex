defmodule BlackboexWeb.Showcase.Sections.ActionRow do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.UI.ActionRow

  def render(assigns) do
    ~H"""
    <.section_header
      title="Action Row"
      description="Horizontal row with title, description, and trailing action. Used for settings and danger-zone rows."
      module="BlackboexWeb.Components.UI.ActionRow"
    />
    <div class="space-y-10">
      <.showcase_block title="Default Variant">
        <.action_row>
          <:title>Change API Name</:title>
          <:description>Update the display name for this API.</:description>
          <:action>
            <.button variant="outline" size="sm">Rename</.button>
          </:action>
        </.action_row>
      </.showcase_block>

      <.showcase_block title="Destructive Variant">
        <.action_row variant="destructive">
          <:title>Delete this API</:title>
          <:description>
            Permanently remove this API and all its data. This cannot be undone.
          </:description>
          <:action>
            <.button variant="destructive" size="sm">Delete API</.button>
          </:action>
        </.action_row>
      </.showcase_block>

      <.showcase_block title="Stacked">
        <div class="space-y-3">
          <.action_row>
            <:title>Transfer Ownership</:title>
            <:description>Move this API to another organization.</:description>
            <:action>
              <.button variant="outline" size="sm">Transfer</.button>
            </:action>
          </.action_row>
          <.action_row variant="destructive">
            <:title>Archive this API</:title>
            <:description>Removes from active list.</:description>
            <:action>
              <.button variant="outline-destructive" size="sm">Archive</.button>
            </:action>
          </.action_row>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
