defmodule BlackboexWeb.Showcase.Sections.SheetShowcase do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Sheet

  @code_right ~S"""
  <.sheet>
    <.sheet_trigger target="demo-sheet-1">
      <.button variant="outline">Open right sheet</.button>
    </.sheet_trigger>
  </.sheet>
  <.sheet_content id="demo-sheet-1" side="right">
    <.sheet_header>
      <.sheet_title>Edit profile</.sheet_title>
      <.sheet_description>Make changes to your profile here.</.sheet_description>
    </.sheet_header>
    <p class="py-4 text-sm text-muted-foreground">Sheet content goes here.</p>
    <.sheet_footer>
      <.sheet_close target="demo-sheet-1">
        <.button variant="outline">Cancel</.button>
      </.sheet_close>
      <.button variant="primary">Save changes</.button>
    </.sheet_footer>
  </.sheet_content>
  """

  @code_left ~S"""
  <.sheet>
    <.sheet_trigger target="demo-sheet-2">
      <.button variant="outline">Open left sheet</.button>
    </.sheet_trigger>
  </.sheet>
  <.sheet_content id="demo-sheet-2" side="left">
    <.sheet_header>
      <.sheet_title>Navigation</.sheet_title>
      <.sheet_description>Mobile navigation panel.</.sheet_description>
    </.sheet_header>
    <p class="py-4 text-sm text-muted-foreground">Navigation items go here.</p>
  </.sheet_content>
  """

  @code_top ~S"""
  <.sheet>
    <.sheet_trigger target="demo-sheet-3">
      <.button variant="outline">Open top sheet</.button>
    </.sheet_trigger>
  </.sheet>
  <.sheet_content id="demo-sheet-3" side="top">
    <.sheet_header>
      <.sheet_title>Notifications</.sheet_title>
      <.sheet_description>Your recent activity.</.sheet_description>
    </.sheet_header>
  </.sheet_content>
  """

  @code_bottom ~S"""
  <.sheet>
    <.sheet_trigger target="demo-sheet-4">
      <.button variant="outline">Open bottom sheet</.button>
    </.sheet_trigger>
  </.sheet>
  <.sheet_content id="demo-sheet-4" side="bottom">
    <.sheet_header>
      <.sheet_title>Quick actions</.sheet_title>
      <.sheet_description>Select an action to perform.</.sheet_description>
    </.sheet_header>
  </.sheet_content>
  """

  @code_minimal ~S"""
  <.sheet>
    <.sheet_trigger target="demo-sheet-5">
      <.button variant="ghost">Open minimal</.button>
    </.sheet_trigger>
  </.sheet>
  <.sheet_content id="demo-sheet-5" side="right">
    <p class="text-sm text-muted-foreground">
      A minimal sheet with no header or footer — just content.
    </p>
  </.sheet_content>
  """

  @code_custom_close ~S"""
  <.sheet>
    <.sheet_trigger target="demo-sheet-6">
      <.button variant="outline">Open with custom close</.button>
    </.sheet_trigger>
  </.sheet>
  <.sheet_content id="demo-sheet-6" side="right">
    <:custom_close_btn>
      <.sheet_close target="demo-sheet-6">
        <.button variant="destructive" size="sm"
          class="absolute top-4 right-4">
          Close
        </.button>
      </.sheet_close>
    </:custom_close_btn>
    <.sheet_header>
      <.sheet_title>Custom close button</.sheet_title>
      <.sheet_description>Uses the custom_close_btn slot.</.sheet_description>
    </.sheet_header>
    <p class="py-4 text-sm text-muted-foreground">
      The default X button is replaced by the custom_close_btn slot content.
    </p>
  </.sheet_content>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_right, @code_right)
      |> assign(:code_left, @code_left)
      |> assign(:code_top, @code_top)
      |> assign(:code_bottom, @code_bottom)
      |> assign(:code_minimal, @code_minimal)
      |> assign(:code_custom_close, @code_custom_close)

    ~H"""
    <.section_header
      title="Sheet"
      description="Slide-in panel anchored to a screen edge. Useful for settings drawers, mobile navigation, and contextual detail panels. side= controls which edge it slides from."
      module="BlackboexWeb.Components.Sheet"
    />
    <div class="space-y-10">
      <.showcase_block title="Right side (default)" code={@code_right}>
        <.sheet>
          <.sheet_trigger target="demo-sheet-1">
            <.button variant="outline">Open right sheet</.button>
          </.sheet_trigger>
        </.sheet>
        <.sheet_content id="demo-sheet-1" side="right">
          <.sheet_header>
            <.sheet_title>Edit profile</.sheet_title>
            <.sheet_description>Make changes to your profile here.</.sheet_description>
          </.sheet_header>
          <p class="py-4 text-sm text-muted-foreground">Sheet content goes here.</p>
          <.sheet_footer>
            <.sheet_close target="demo-sheet-1">
              <.button variant="outline">Cancel</.button>
            </.sheet_close>
            <.button variant="primary">Save changes</.button>
          </.sheet_footer>
        </.sheet_content>
      </.showcase_block>

      <.showcase_block title="Left side" code={@code_left}>
        <.sheet>
          <.sheet_trigger target="demo-sheet-2">
            <.button variant="outline">Open left sheet</.button>
          </.sheet_trigger>
        </.sheet>
        <.sheet_content id="demo-sheet-2" side="left">
          <.sheet_header>
            <.sheet_title>Navigation</.sheet_title>
            <.sheet_description>Mobile navigation panel.</.sheet_description>
          </.sheet_header>
          <p class="py-4 text-sm text-muted-foreground">Navigation items go here.</p>
        </.sheet_content>
      </.showcase_block>

      <.showcase_block title="Top side" code={@code_top}>
        <.sheet>
          <.sheet_trigger target="demo-sheet-3">
            <.button variant="outline">Open top sheet</.button>
          </.sheet_trigger>
        </.sheet>
        <.sheet_content id="demo-sheet-3" side="top">
          <.sheet_header>
            <.sheet_title>Notifications</.sheet_title>
            <.sheet_description>Your recent activity.</.sheet_description>
          </.sheet_header>
          <p class="py-4 text-sm text-muted-foreground">Notification items go here.</p>
        </.sheet_content>
      </.showcase_block>

      <.showcase_block title="Bottom side" code={@code_bottom}>
        <.sheet>
          <.sheet_trigger target="demo-sheet-4">
            <.button variant="outline">Open bottom sheet</.button>
          </.sheet_trigger>
        </.sheet>
        <.sheet_content id="demo-sheet-4" side="bottom">
          <.sheet_header>
            <.sheet_title>Quick actions</.sheet_title>
            <.sheet_description>Select an action to perform.</.sheet_description>
          </.sheet_header>
          <p class="py-4 text-sm text-muted-foreground">Action items go here.</p>
        </.sheet_content>
      </.showcase_block>

      <.showcase_block title="Minimal (no header/footer)" code={@code_minimal}>
        <.sheet>
          <.sheet_trigger target="demo-sheet-5">
            <.button variant="ghost">Open minimal</.button>
          </.sheet_trigger>
        </.sheet>
        <.sheet_content id="demo-sheet-5" side="right">
          <p class="text-sm text-muted-foreground">
            A minimal sheet with no header or footer — just content.
          </p>
        </.sheet_content>
      </.showcase_block>

      <.showcase_block
        title="With custom close button (custom_close_btn slot)"
        code={@code_custom_close}
      >
        <.sheet>
          <.sheet_trigger target="demo-sheet-6">
            <.button variant="outline">Open with custom close</.button>
          </.sheet_trigger>
        </.sheet>
        <.sheet_content id="demo-sheet-6" side="right">
          <:custom_close_btn>
            <.sheet_close target="demo-sheet-6">
              <.button
                variant="destructive"
                size="sm"
                class="absolute top-4 right-4"
              >
                Close
              </.button>
            </.sheet_close>
          </:custom_close_btn>
          <.sheet_header>
            <.sheet_title>Custom close button</.sheet_title>
            <.sheet_description>Uses the custom_close_btn slot.</.sheet_description>
          </.sheet_header>
          <p class="py-4 text-sm text-muted-foreground">
            The default X button is replaced by the custom_close_btn slot content.
          </p>
        </.sheet_content>
      </.showcase_block>
    </div>
    """
  end
end
