defmodule BlackboexWeb.Showcase.Sections.FieldLabel do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.UI.FieldLabel

  def render(assigns) do
    ~H"""
    <.section_header
      title="Field Label"
      description="Compact label with optional leading icon for inline form fields. Used in the flow editor and schema builder."
      module="BlackboexWeb.Components.UI.FieldLabel"
    />
    <div class="space-y-10 max-w-xl">
      <.showcase_block title="With Icon">
        <div class="space-y-3">
          <.field_label icon="hero-key" icon_color="text-accent-amber">API Key Name</.field_label>
          <.field_label icon="hero-code-bracket" icon_color="text-accent-purple">Code</.field_label>
          <.field_label icon="hero-globe-alt" icon_color="text-accent-blue">Endpoint</.field_label>
        </div>
      </.showcase_block>

      <.showcase_block title="Without Icon">
        <.field_label>Plain Field Label</.field_label>
      </.showcase_block>
    </div>
    """
  end
end
