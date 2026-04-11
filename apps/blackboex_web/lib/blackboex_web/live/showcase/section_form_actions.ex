defmodule BlackboexWeb.Showcase.Sections.FormActions do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  def render(assigns) do
    ~H"""
    <.section_header
      title="Form Actions"
      description="Button row for form/modal footers. Alignment options: start, center, end, between. Spacing: tight or default."
      module="BlackboexWeb.Components.Shared.FormActions"
    />
    <div class="space-y-10">
      <.showcase_block title="End Aligned (default)">
        <.form_actions>
          <.button variant="outline">Cancel</.button>
          <.button variant="primary">Save</.button>
        </.form_actions>
      </.showcase_block>

      <.showcase_block title="Between">
        <.form_actions align="between">
          <.button variant="destructive">Delete</.button>
          <.button variant="primary">Save</.button>
        </.form_actions>
      </.showcase_block>

      <.showcase_block title="Start">
        <.form_actions align="start">
          <.button variant="outline">Back</.button>
          <.button variant="primary">Next</.button>
        </.form_actions>
      </.showcase_block>

      <.showcase_block title="Center">
        <.form_actions align="center">
          <.button variant="primary">Submit</.button>
        </.form_actions>
      </.showcase_block>

      <.showcase_block title="Tight Spacing">
        <.form_actions spacing="tight">
          <.button variant="outline">Cancel</.button>
          <.button variant="primary">Save</.button>
        </.form_actions>
      </.showcase_block>
    </div>
    """
  end
end
