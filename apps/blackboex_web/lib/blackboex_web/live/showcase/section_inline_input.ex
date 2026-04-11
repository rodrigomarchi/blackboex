defmodule BlackboexWeb.Showcase.Sections.InlineInput do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.UI.InlineInput

  @code_types ~S"""
  <.inline_input type="text" value="text input" />
  <.inline_input type="number" value="42" />
  <.inline_input type="password" value="secret" />
  <.inline_input type="email" value="user@example.com" />
  <.inline_input type="search" value="search query" />
  <.inline_input type="tel" value="+1 555 0100" />
  <.inline_input type="url" value="https://example.com" />
  """

  @code_placeholder ~S"""
  <.inline_input type="text" placeholder="Enter a name..." />
  <.inline_input type="email" placeholder="you@example.com" />
  <.inline_input type="number" placeholder="0" />
  """

  @code_disabled ~S"""
  <.inline_input type="text" value="Cannot edit" disabled />
  """

  @code_readonly ~S"""
  <.inline_input type="text" value="Read-only value" readonly />
  """

  @code_in_context ~S"""
  <div class="divide-y rounded-lg border">
    <div class="flex items-center gap-4 px-4 py-2 text-sm">
      <span class="w-32 shrink-0 font-medium text-muted-foreground">API name</span>
      <.inline_input type="text" value="my-api" class="border-0 px-0 focus-visible:ring-0" />
    </div>
    <div class="flex items-center gap-4 px-4 py-2 text-sm">
      <span class="w-32 shrink-0 font-medium text-muted-foreground">Timeout (ms)</span>
      <.inline_input type="number" value="5000" class="border-0 px-0 focus-visible:ring-0" />
    </div>
  </div>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_types, @code_types)
      |> assign(:code_placeholder, @code_placeholder)
      |> assign(:code_disabled, @code_disabled)
      |> assign(:code_readonly, @code_readonly)
      |> assign(:code_in_context, @code_in_context)

    ~H"""
    <.section_header
      title="InlineInput"
      description="Borderless inline input for use in compact table cells, inline editors, or settings rows where a full-border input would be visually heavy."
      module="BlackboexWeb.Components.UI.InlineInput"
    />
    <div class="space-y-10">
      <.showcase_block title="All types" code={@code_types}>
        <div class="space-y-3 max-w-sm">
          <div class="flex items-center gap-3">
            <span class="w-20 text-xs text-muted-foreground">text</span>
            <.inline_input type="text" value="text input" />
          </div>
          <div class="flex items-center gap-3">
            <span class="w-20 text-xs text-muted-foreground">number</span>
            <.inline_input type="number" value="42" />
          </div>
          <div class="flex items-center gap-3">
            <span class="w-20 text-xs text-muted-foreground">password</span>
            <.inline_input type="password" value="secret" />
          </div>
          <div class="flex items-center gap-3">
            <span class="w-20 text-xs text-muted-foreground">email</span>
            <.inline_input type="email" value="user@example.com" />
          </div>
          <div class="flex items-center gap-3">
            <span class="w-20 text-xs text-muted-foreground">search</span>
            <.inline_input type="search" value="search query" />
          </div>
          <div class="flex items-center gap-3">
            <span class="w-20 text-xs text-muted-foreground">tel</span>
            <.inline_input type="tel" value="+1 555 0100" />
          </div>
          <div class="flex items-center gap-3">
            <span class="w-20 text-xs text-muted-foreground">url</span>
            <.inline_input type="url" value="https://example.com" />
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="With placeholder" code={@code_placeholder}>
        <div class="space-y-3 max-w-sm">
          <.inline_input type="text" placeholder="Enter a name..." />
          <.inline_input type="email" placeholder="you@example.com" />
          <.inline_input type="number" placeholder="0" />
        </div>
      </.showcase_block>

      <.showcase_block title="Disabled" code={@code_disabled}>
        <div class="max-w-sm">
          <.inline_input type="text" value="Cannot edit" disabled />
        </div>
      </.showcase_block>

      <.showcase_block title="Readonly" code={@code_readonly}>
        <div class="max-w-sm">
          <.inline_input type="text" value="Read-only value" readonly />
        </div>
      </.showcase_block>

      <.showcase_block title="In context (table cell)" code={@code_in_context}>
        <div class="divide-y rounded-lg border max-w-md">
          <div class="flex items-center gap-4 px-4 py-2 text-sm">
            <span class="w-32 shrink-0 font-medium text-muted-foreground">API name</span>
            <.inline_input type="text" value="my-api" class="border-0 px-0 focus-visible:ring-0" />
          </div>
          <div class="flex items-center gap-4 px-4 py-2 text-sm">
            <span class="w-32 shrink-0 font-medium text-muted-foreground">Timeout (ms)</span>
            <.inline_input
              type="number"
              value="5000"
              class="border-0 px-0 focus-visible:ring-0"
            />
          </div>
          <div class="flex items-center gap-4 px-4 py-2 text-sm">
            <span class="w-32 shrink-0 font-medium text-muted-foreground">Base path</span>
            <.inline_input
              type="text"
              value="/api/v1"
              class="border-0 px-0 focus-visible:ring-0"
            />
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
