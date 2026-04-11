defmodule BlackboexWeb.Showcase.Sections.DropdownMenu do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.DropdownMenu
  import BlackboexWeb.Components.Separator

  @code_shortcut ~S"""
  <.dropdown_menu_item>
    Profile
    <.dropdown_menu_shortcut>⌘P</.dropdown_menu_shortcut>
  </.dropdown_menu_item>
  <.dropdown_menu_item>
    Settings
    <.dropdown_menu_shortcut>⌘S</.dropdown_menu_shortcut>
  </.dropdown_menu_item>
  """

  @code_side_align ~S"""
  <%!-- side: top | bottom (default) | left | right --%>
  <.dropdown_menu_content side="bottom" align="start">
    ...
  </.dropdown_menu_content>

  <%!-- align: start (default) | center | end --%>
  <.dropdown_menu_content side="bottom" align="end">
    ...
  </.dropdown_menu_content>
  """

  @code_as_tag ~S"""
  <%!-- as_tag changes the trigger wrapper element (default: "div") --%>
  <.dropdown_menu_trigger as_tag="span">
    <.button variant="outline">Span Trigger</.button>
  </.dropdown_menu_trigger>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_shortcut, @code_shortcut)
      |> assign(:code_side_align, @code_side_align)
      |> assign(:code_as_tag, @code_as_tag)

    ~H"""
    <.section_header
      title="Dropdown Menu"
      description="Click-triggered dropdown with menu items, shortcuts, separators. Uses JS toggle for open/close state."
      module="BlackboexWeb.Components.DropdownMenu"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic Dropdown">
        <.dropdown_menu>
          <.dropdown_menu_trigger>
            <.button variant="outline">
              Actions <.icon name="hero-chevron-down" class="size-3 ml-1" />
            </.button>
          </.dropdown_menu_trigger>
          <.dropdown_menu_content>
            <.button variant="ghost" size="list-item">
              <.icon name="hero-pencil" class="size-4" /> Edit
            </.button>
            <.button variant="ghost" size="list-item">
              <.icon name="hero-document-duplicate" class="size-4" /> Duplicate
            </.button>
            <.separator />
            <.button variant="ghost" size="list-item" class="text-destructive">
              <.icon name="hero-trash" class="size-4" /> Delete
            </.button>
          </.dropdown_menu_content>
        </.dropdown_menu>
      </.showcase_block>

      <.showcase_block title="With Shortcuts" code={@code_shortcut}>
        <.dropdown_menu>
          <.dropdown_menu_trigger>
            <.button variant="outline">
              Account <.icon name="hero-chevron-down" class="size-3 ml-1" />
            </.button>
          </.dropdown_menu_trigger>
          <.dropdown_menu_content>
            <.button variant="ghost" size="list-item">
              Profile
              <.dropdown_menu_shortcut>⌘P</.dropdown_menu_shortcut>
            </.button>
            <.button variant="ghost" size="list-item">
              Billing
              <.dropdown_menu_shortcut>⌘B</.dropdown_menu_shortcut>
            </.button>
            <.separator />
            <.button variant="ghost" size="list-item">
              Settings
              <.dropdown_menu_shortcut>⌘S</.dropdown_menu_shortcut>
            </.button>
            <.button variant="ghost" size="list-item">
              Keyboard shortcuts
              <.dropdown_menu_shortcut>⌘K</.dropdown_menu_shortcut>
            </.button>
          </.dropdown_menu_content>
        </.dropdown_menu>
      </.showcase_block>

      <.showcase_block title="Side & Align" code={@code_side_align}>
        <div class="flex flex-wrap gap-6">
          <.dropdown_menu>
            <.dropdown_menu_trigger>
              <.button variant="outline" size="sm">Bottom + Start (default)</.button>
            </.dropdown_menu_trigger>
            <.dropdown_menu_content side="bottom" align="start">
              <.button variant="ghost" size="list-item">Item 1</.button>
              <.button variant="ghost" size="list-item">Item 2</.button>
            </.dropdown_menu_content>
          </.dropdown_menu>

          <.dropdown_menu>
            <.dropdown_menu_trigger>
              <.button variant="outline" size="sm">Bottom + End</.button>
            </.dropdown_menu_trigger>
            <.dropdown_menu_content side="bottom" align="end">
              <.button variant="ghost" size="list-item">Item 1</.button>
              <.button variant="ghost" size="list-item">Item 2</.button>
            </.dropdown_menu_content>
          </.dropdown_menu>

          <.dropdown_menu>
            <.dropdown_menu_trigger>
              <.button variant="outline" size="sm">Top + Start</.button>
            </.dropdown_menu_trigger>
            <.dropdown_menu_content side="top" align="start">
              <.button variant="ghost" size="list-item">Item 1</.button>
              <.button variant="ghost" size="list-item">Item 2</.button>
            </.dropdown_menu_content>
          </.dropdown_menu>

          <.dropdown_menu>
            <.dropdown_menu_trigger>
              <.button variant="outline" size="sm">Right + Start</.button>
            </.dropdown_menu_trigger>
            <.dropdown_menu_content side="right" align="start">
              <.button variant="ghost" size="list-item">Item 1</.button>
              <.button variant="ghost" size="list-item">Item 2</.button>
            </.dropdown_menu_content>
          </.dropdown_menu>
        </div>
      </.showcase_block>

      <.showcase_block title="as_tag on Trigger" code={@code_as_tag}>
        <.dropdown_menu>
          <.dropdown_menu_trigger as_tag="span">
            <.button variant="outline">
              Span Trigger <.icon name="hero-chevron-down" class="size-3 ml-1" />
            </.button>
          </.dropdown_menu_trigger>
          <.dropdown_menu_content>
            <.button variant="ghost" size="list-item">Option A</.button>
            <.button variant="ghost" size="list-item">Option B</.button>
          </.dropdown_menu_content>
        </.dropdown_menu>
      </.showcase_block>
    </div>
    """
  end
end
