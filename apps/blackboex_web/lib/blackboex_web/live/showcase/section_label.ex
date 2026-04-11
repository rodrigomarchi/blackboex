defmodule BlackboexWeb.Showcase.Sections.Label do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Label

  def render(assigns) do
    ~H"""
    <.section_header
      title="Label"
      description="Standard HTML label with consistent styling. Used for form fields."
      module="BlackboexWeb.Components.Label"
    />
    <div class="space-y-10 max-w-xl">
      <.showcase_block title="Basic Label">
        <div class="space-y-1">
          <.label for="label-demo">Field Label</.label>
          <.input
            type="text"
            id="label-demo"
            name="label-demo"
            value=""
            placeholder="Input with label"
          />
        </div>
      </.showcase_block>

      <.showcase_block title="Without for Attribute">
        <.label>Standalone Label</.label>
      </.showcase_block>
    </div>
    """
  end
end
