defmodule BlackboexWeb.Showcase.Sections.Badge do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Badge

  @code_variants ~S"""
  <.badge variant="default">default</.badge>
  <.badge variant="secondary">secondary</.badge>
  <.badge variant="destructive">destructive</.badge>
  <.badge variant="outline">outline</.badge>
  <.badge variant="success">success</.badge>
  <.badge variant="warning">warning</.badge>
  <.badge variant="info">info</.badge>
  <.badge variant="status">status</.badge>
  """

  def render(assigns) do
    assigns = assign(assigns, :code_variants, @code_variants)

    ~H"""
    <.section_header
      title="Badge"
      description="Inline status or category indicator. Supports 8 variants and 2 sizes."
      module="BlackboexWeb.Components.Badge"
    />
    <div class="space-y-10">
      <.showcase_block title="Variants" code={@code_variants}>
        <div class="flex flex-wrap gap-3">
          <.badge variant="default">default</.badge>
          <.badge variant="secondary">secondary</.badge>
          <.badge variant="outline">outline</.badge>
          <.badge variant="destructive">destructive</.badge>
          <.badge variant="success">success</.badge>
          <.badge variant="warning">warning</.badge>
          <.badge variant="info">info</.badge>
          <.badge variant="status">status</.badge>
        </div>
      </.showcase_block>

      <.showcase_block title="Sizes">
        <div class="flex flex-wrap items-center gap-3">
          <.badge variant="default" size="default">default</.badge>
          <.badge variant="default" size="xs">xs</.badge>
        </div>
      </.showcase_block>

      <.showcase_block title="With Icons">
        <div class="flex flex-wrap gap-3">
          <.badge variant="success">
            <.icon name="hero-check-circle" class="size-3 mr-1" />Published
          </.badge>
          <.badge variant="warning"><.icon name="hero-clock" class="size-3 mr-1" />Pending</.badge>
          <.badge variant="destructive">
            <.icon name="hero-x-circle" class="size-3 mr-1" />Failed
          </.badge>
          <.badge variant="info">
            <.icon name="hero-information-circle" class="size-3 mr-1" />Info
          </.badge>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
