defmodule BlackboexWeb.Showcase.Sections.Button do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  @code_variants ~S"""
  <.button variant="default">default</.button>
  <.button variant="primary">primary</.button>
  <.button variant="secondary">secondary</.button>
  <.button variant="destructive">destructive</.button>
  <.button variant="outline">outline</.button>
  <.button variant="outline-destructive">outline-destructive</.button>
  <.button variant="ghost">ghost</.button>
  <.button variant="ghost-muted">ghost-muted</.button>
  <.button variant="ghost-dark">ghost-dark</.button>
  <.button variant="success">success</.button>
  <.button variant="info">info</.button>
  <.button variant="link">link</.button>
  """

  @code_sizes ~S"""
  <.button variant="primary" size="lg">lg</.button>
  <.button variant="primary" size="default">default</.button>
  <.button variant="primary" size="sm">sm</.button>
  <.button variant="primary" size="compact">compact</.button>
  <.button variant="primary" size="pill">pill</.button>
  <.button variant="primary" size="micro">micro</.button>
  <.button variant="primary" size="icon">
    <.icon name="hero-plus" class="size-4" />
  </.button>
  <.button variant="outline" size="icon-sm">
    <.icon name="hero-plus" class="size-4" />
  </.button>
  <.button variant="ghost" size="icon-xs">
    <.icon name="hero-plus" class="size-3" />
  </.button>
  <.button variant="ghost" size="list-item">
    <.icon name="hero-pencil" class="size-4" /> Menu item
  </.button>
  """

  @code_nav ~S"""
  <.button variant="primary" navigate={"/showcase/badge"}>
    Navigate to Badge
  </.button>
  """

  @code_type ~S"""
  <.button type="submit" variant="primary">Submit (type="submit")</.button>
  <.button type="button" variant="outline">Button (type="button")</.button>
  <.button type="reset" variant="ghost">Reset (type="reset")</.button>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_variants, @code_variants)
      |> assign(:code_sizes, @code_sizes)
      |> assign(:code_nav, @code_nav)
      |> assign(:code_type, @code_type)

    ~H"""
    <.section_header
      title="Button"
      description="Polymorphic button. Renders <button> by default, or <.link> when navigate/href/patch is provided. Supports 12 variants and 10 sizes."
      module="BlackboexWeb.Components.Button"
    />
    <div class="space-y-10">
      <.showcase_block title="Variants" code={@code_variants}>
        <div class="flex flex-wrap gap-3">
          <.button variant="default">default</.button>
          <.button variant="primary">primary</.button>
          <.button variant="secondary">secondary</.button>
          <.button variant="destructive">destructive</.button>
          <.button variant="outline">outline</.button>
          <.button variant="outline-destructive">outline-destructive</.button>
          <.button variant="ghost">ghost</.button>
          <.button variant="ghost-muted">ghost-muted</.button>
          <.button variant="success">success</.button>
          <.button variant="info">info</.button>
          <.button variant="link">link</.button>
        </div>
        <div class="mt-4 bg-gray-900 rounded p-3 flex gap-2">
          <.button variant="ghost-dark">ghost-dark</.button>
          <.button variant="ghost-dark">
            <.icon name="hero-cog-6-tooth" class="size-4" /> ghost-dark with icon
          </.button>
        </div>
      </.showcase_block>

      <.showcase_block title="Sizes" code={@code_sizes}>
        <div class="flex flex-wrap items-center gap-3">
          <.button variant="primary" size="lg">lg</.button>
          <.button variant="primary" size="default">default</.button>
          <.button variant="primary" size="sm">sm</.button>
          <.button variant="primary" size="compact">compact</.button>
          <.button variant="primary" size="pill">pill</.button>
          <.button variant="primary" size="micro">micro</.button>
          <.button variant="primary" size="icon">
            <.icon name="hero-plus" class="size-4" />
          </.button>
          <.button variant="outline" size="icon-sm">
            <.icon name="hero-plus" class="size-4" />
          </.button>
          <.button variant="ghost" size="icon-xs">
            <.icon name="hero-plus" class="size-3" />
          </.button>
        </div>
      </.showcase_block>

      <.showcase_block title="List Item Size">
        <div class="max-w-xs rounded-lg border bg-card">
          <.button variant="ghost" size="list-item">
            <.icon name="hero-pencil" class="size-4" /> Edit
          </.button>
          <.button variant="ghost" size="list-item">
            <.icon name="hero-document-duplicate" class="size-4" /> Duplicate
          </.button>
          <.button variant="ghost" size="list-item" class="text-destructive">
            <.icon name="hero-trash" class="size-4" /> Delete
          </.button>
        </div>
      </.showcase_block>

      <.showcase_block title="With Icons">
        <div class="flex flex-wrap gap-3">
          <.button variant="primary"><.icon name="hero-plus" class="size-4" /> Create API</.button>
          <.button variant="outline">
            <.icon name="hero-arrow-down-tray" class="size-4" /> Export
          </.button>
          <.button variant="destructive"><.icon name="hero-trash" class="size-4" /> Delete</.button>
          <.button variant="ghost"><.icon name="hero-pencil" class="size-4" /> Edit</.button>
        </div>
      </.showcase_block>

      <.showcase_block title="Disabled State">
        <div class="flex flex-wrap gap-3">
          <.button variant="primary" disabled>primary</.button>
          <.button variant="outline" disabled>outline</.button>
          <.button variant="destructive" disabled>destructive</.button>
        </div>
      </.showcase_block>

      <.showcase_block title="Type Attr" code={@code_type}>
        <div class="flex flex-wrap gap-3">
          <.button type="submit" variant="primary">Submit (type="submit")</.button>
          <.button type="button" variant="outline">Button (type="button")</.button>
          <.button type="reset" variant="ghost">Reset (type="reset")</.button>
        </div>
      </.showcase_block>

      <.showcase_block title="As Navigation Link" code={@code_nav}>
        <div class="flex flex-wrap gap-3">
          <.button variant="primary" navigate="/showcase/badge">Navigate to Badge</.button>
          <.button variant="outline" href="#top">Href anchor</.button>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
