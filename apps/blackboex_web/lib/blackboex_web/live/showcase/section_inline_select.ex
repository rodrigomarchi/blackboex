defmodule BlackboexWeb.Showcase.Sections.InlineSelect do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.UI.InlineSelect

  @options [{"Option A", "a"}, {"Option B", "b"}, {"Option C", "c"}]

  @code_basic ~S"""
  <.inline_select options={[{"Option A", "a"}, {"Option B", "b"}, {"Option C", "c"}]} />
  """

  @code_selected ~S"""
  <.inline_select
    options={[{"Option A", "a"}, {"Option B", "b"}, {"Option C", "c"}]}
    value="b"
  />
  """

  @code_disabled ~S"""
  <.inline_select
    options={[{"Option A", "a"}, {"Option B", "b"}, {"Option C", "c"}]}
    value="a"
    disabled
  />
  """

  @code_in_context ~S"""
  <div class="divide-y rounded-lg border">
    <div class="flex items-center gap-4 px-4 py-2 text-sm">
      <span class="w-32 shrink-0 font-medium text-muted-foreground">HTTP method</span>
      <.inline_select
        options={[{"GET", "get"}, {"POST", "post"}, {"PUT", "put"}, {"DELETE", "delete"}]}
        value="get"
        class="border-0 px-0 focus-visible:ring-0"
      />
    </div>
  </div>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:options, @options)
      |> assign(:code_basic, @code_basic)
      |> assign(:code_selected, @code_selected)
      |> assign(:code_disabled, @code_disabled)
      |> assign(:code_in_context, @code_in_context)

    ~H"""
    <.section_header
      title="InlineSelect"
      description="Borderless inline select for compact dropdown contexts like table cells or inline settings."
      module="BlackboexWeb.Components.UI.InlineSelect"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic" code={@code_basic}>
        <div class="max-w-xs">
          <.inline_select options={@options} />
        </div>
      </.showcase_block>

      <.showcase_block title="With selected value" code={@code_selected}>
        <div class="max-w-xs">
          <.inline_select options={@options} value="b" />
        </div>
      </.showcase_block>

      <.showcase_block title="Disabled" code={@code_disabled}>
        <div class="max-w-xs">
          <.inline_select options={@options} value="a" disabled />
        </div>
      </.showcase_block>

      <.showcase_block title="In context" code={@code_in_context}>
        <div class="divide-y rounded-lg border max-w-md">
          <div class="flex items-center gap-4 px-4 py-2 text-sm">
            <span class="w-32 shrink-0 font-medium text-muted-foreground">HTTP method</span>
            <.inline_select
              options={[{"GET", "get"}, {"POST", "post"}, {"PUT", "put"}, {"DELETE", "delete"}]}
              value="get"
              class="border-0 px-0 focus-visible:ring-0"
            />
          </div>
          <div class="flex items-center gap-4 px-4 py-2 text-sm">
            <span class="w-32 shrink-0 font-medium text-muted-foreground">Environment</span>
            <.inline_select
              options={[
                {"Production", "production"},
                {"Staging", "staging"},
                {"Development", "development"}
              ]}
              value="staging"
              class="border-0 px-0 focus-visible:ring-0"
            />
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
