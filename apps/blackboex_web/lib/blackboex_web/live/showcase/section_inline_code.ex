defmodule BlackboexWeb.Showcase.Sections.InlineCode do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.InlineCode

  def render(assigns) do
    ~H"""
    <.section_header
      title="Inline Code"
      description="Inline code display for code snippets and tokens. Two variants: default (inline) and block."
      module="BlackboexWeb.Components.Shared.InlineCode"
    />
    <div class="space-y-10 max-w-xl">
      <.showcase_block title="Default (Inline)">
        <p class="text-sm">
          Use the
          <.inline_code>fetch/2</.inline_code>
          function to make HTTP requests.
          The response includes a
          <.inline_code>status_code</.inline_code>
          field.
        </p>
      </.showcase_block>

      <.showcase_block title="Block">
        <.inline_code variant="block">
          curl -X GET https://api.example.com/v1/weather?city=london
        </.inline_code>
      </.showcase_block>
    </div>
    """
  end
end
