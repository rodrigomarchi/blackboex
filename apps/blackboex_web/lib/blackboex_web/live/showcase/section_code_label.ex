defmodule BlackboexWeb.Showcase.Sections.CodeLabel do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Editor.CodeLabel

  @code_default ~S"""
  <.code_label>elixir</.code_label>
  <.code_label>json</.code_label>
  """

  @code_dark ~S"""
  <div class="bg-editor-bg p-4 rounded-lg">
    <.code_label variant="dark">elixir</.code_label>
    <.code_label variant="dark">json</.code_label>
  </div>
  """

  @code_multiple ~S"""
  <div class="flex items-center gap-3">
    <.code_label>Code</.code_label>
    <.code_label>Tests</.code_label>
    <.code_label>Output</.code_label>
    <.code_label>Elixir</.code_label>
  </div>
  """

  @code_custom ~S"""
  <.code_label class="text-xs text-accent-sky">handler.ex</.code_label>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_default, @code_default)
      |> assign(:code_dark, @code_dark)
      |> assign(:code_multiple, @code_multiple)
      |> assign(:code_custom, @code_custom)

    ~H"""
    <.section_header
      title="CodeLabel"
      description="Small pill label for code sections. Use inside editor panels to label code blocks, file tabs, or language indicators. variant=default is light (for light bg); variant=dark is for the dark editor background."
      module="BlackboexWeb.Components.Editor.CodeLabel"
    />
    <div class="space-y-10">
      <.showcase_block title="Default variant" code={@code_default}>
        <div class="flex items-center gap-3">
          <.code_label>elixir</.code_label>
          <.code_label>json</.code_label>
        </div>
      </.showcase_block>

      <.showcase_block title="Dark variant" code={@code_dark}>
        <div class="bg-editor-bg p-4 rounded-lg flex items-center gap-3">
          <.code_label variant="dark">elixir</.code_label>
          <.code_label variant="dark">json</.code_label>
        </div>
      </.showcase_block>

      <.showcase_block title="Multiple labels" code={@code_multiple}>
        <div class="flex items-center gap-3">
          <.code_label>Code</.code_label>
          <.code_label>Tests</.code_label>
          <.code_label>Output</.code_label>
          <.code_label>Elixir</.code_label>
        </div>
      </.showcase_block>

      <.showcase_block title="Custom class" code={@code_custom}>
        <.code_label class="text-xs text-accent-sky">handler.ex</.code_label>
      </.showcase_block>
    </div>
    """
  end
end
