defmodule BlackboexWeb.Showcase.Sections.InlineTextarea do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.UI.InlineTextarea

  @code_default ~S"""
  <.inline_textarea placeholder="Enter a description..." />
  """

  @code_rows ~S"""
  <.inline_textarea rows="2" placeholder="2 rows" />
  <.inline_textarea rows="4" placeholder="4 rows" />
  <.inline_textarea rows="6" placeholder="6 rows" />
  """

  @code_disabled ~S"""
  <.inline_textarea value="This field is disabled." disabled />
  """

  @code_with_value ~S"""
  <.inline_textarea value={"This is some prefilled content.\nLine two of the content."} rows="4" />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_default, @code_default)
      |> assign(:code_rows, @code_rows)
      |> assign(:code_disabled, @code_disabled)
      |> assign(:code_with_value, @code_with_value)

    ~H"""
    <.section_header
      title="InlineTextarea"
      description="Borderless inline textarea for compact multi-line editing contexts."
      module="BlackboexWeb.Components.UI.InlineTextarea"
    />
    <div class="space-y-10">
      <.showcase_block title="Default" code={@code_default}>
        <div class="max-w-md">
          <.inline_textarea placeholder="Enter a description..." />
        </div>
      </.showcase_block>

      <.showcase_block title="Rows variants" code={@code_rows}>
        <div class="space-y-4 max-w-md">
          <div>
            <p class="text-xs text-muted-foreground mb-1">rows="2"</p>
            <.inline_textarea rows="2" placeholder="2 rows" />
          </div>
          <div>
            <p class="text-xs text-muted-foreground mb-1">rows="4"</p>
            <.inline_textarea rows="4" placeholder="4 rows" />
          </div>
          <div>
            <p class="text-xs text-muted-foreground mb-1">rows="6"</p>
            <.inline_textarea rows="6" placeholder="6 rows" />
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Disabled" code={@code_disabled}>
        <div class="max-w-md">
          <.inline_textarea value="This field is disabled." disabled />
        </div>
      </.showcase_block>

      <.showcase_block title="With value" code={@code_with_value}>
        <div class="max-w-md">
          <.inline_textarea
            value={"This is some prefilled content.\nLine two of the content."}
            rows="4"
          />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
