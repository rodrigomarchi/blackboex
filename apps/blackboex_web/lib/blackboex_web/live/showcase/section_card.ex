defmodule BlackboexWeb.Showcase.Sections.Card do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Card

  @code_anatomy ~S"""
  <.card>
    <.card_header>
      <.card_title>Card Title</.card_title>
      <.card_description>Description.</.card_description>
    </.card_header>
    <.card_content>
      <p>Main body content.</p>
    </.card_content>
    <.card_footer>
      <.button variant="primary" size="sm">Action</.button>
    </.card_footer>
  </.card>
  """

  @code_compact ~S"""
  <.card>
    <.card_header size="compact">
      <.card_title size="label">Compact Header</.card_title>
    </.card_header>
    <.card_content size="compact">
      <p>Compact content with tighter padding.</p>
    </.card_content>
  </.card>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_anatomy, @code_anatomy)
      |> assign(:code_compact, @code_compact)

    ~H"""
    <.section_header
      title="Card"
      description="Container with header, content, and footer slots. Used for top-level groupings with shadow and rounded-xl."
      module="BlackboexWeb.Components.Card"
    />
    <div class="space-y-10">
      <.showcase_block title="Full Anatomy" code={@code_anatomy}>
        <div class="max-w-sm">
          <.card>
            <.card_header>
              <.card_title>Card Title</.card_title>
              <.card_description>
                Optional supporting description text below the title.
              </.card_description>
            </.card_header>
            <.card_content>
              <p class="text-sm text-muted-foreground">Main body content goes here.</p>
            </.card_content>
            <.card_footer>
              <.button variant="primary" size="sm">Action</.button>
              <.button variant="outline" size="sm">Cancel</.button>
            </.card_footer>
          </.card>
        </div>
      </.showcase_block>

      <.showcase_block title="Content Only">
        <div class="max-w-sm">
          <.card>
            <.card_content standalone>
              <p class="text-sm">Minimal card with only content -- no header or footer needed.</p>
            </.card_content>
          </.card>
        </div>
      </.showcase_block>

      <.showcase_block title="Compact Size" code={@code_compact}>
        <div class="max-w-sm">
          <.card>
            <.card_header size="compact">
              <.card_title size="label">Compact Header</.card_title>
            </.card_header>
            <.card_content size="compact">
              <p class="text-sm text-muted-foreground">
                Compact content uses tighter padding (px-4 pb-3). The title uses label size
                (uppercase, smaller text, muted color).
              </p>
            </.card_content>
          </.card>
        </div>
      </.showcase_block>

      <.showcase_block title="Grid Layout">
        <div class="grid grid-cols-3 gap-4">
          <.card :for={i <- 1..3}>
            <.card_header>
              <.card_title>Card {i}</.card_title>
            </.card_header>
            <.card_content>
              <p class="text-sm text-muted-foreground">Content for card {i}.</p>
            </.card_content>
          </.card>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
