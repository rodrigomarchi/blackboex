defmodule BlackboexWeb.Showcase.Sections.Modal do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.InlineCode

  @code_usage ~S"""
  # In mount:
  {:ok, assign(socket, show_modal: false)}

  # In handle_event:
  def handle_event("open_modal", _, socket),
    do: {:noreply, assign(socket, show_modal: true)}
  def handle_event("close_modal", _, socket),
    do: {:noreply, assign(socket, show_modal: false)}

  # In template:
  <.modal show={@show_modal} on_close="close_modal" title="Confirm">
    <p>Are you sure?</p>
  </.modal>
  """

  @code_no_title ~S"""
  <.modal show={@show_modal} on_close="close_modal">
    <p>Modal without a title -- just content.</p>
  </.modal>
  """

  @code_custom_width ~S"""
  <.modal show={@show_modal} on_close="close_modal"
    title="Wide Modal" class="max-w-2xl">
    <p>Custom width via the class attr.</p>
  </.modal>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_usage, @code_usage)
      |> assign(:code_no_title, @code_no_title)
      |> assign(:code_custom_width, @code_custom_width)

    ~H"""
    <.section_header
      title="Modal"
      description="Dialog overlay with backdrop, close button, and keyboard support (Escape). Controlled via assigns and events. Attrs: show (required), on_close (required), title, class."
      module="BlackboexWeb.Components.Modal"
    />
    <div class="space-y-10">
      <.showcase_block title="Live Modal" code={@code_usage}>
        <div class="space-y-3">
          <p class="text-sm text-muted-foreground">
            Modals are event-driven. Use
            <.inline_code>show</.inline_code>
            and
            <.inline_code>on_close</.inline_code>
            assigns to control visibility. The modal is rendered by ShowcaseLive at the page level.
          </p>
          <.button variant="primary" phx-click="open_modal">Open Modal</.button>
        </div>
      </.showcase_block>

      <.showcase_block title="Without Title" code={@code_no_title}>
        <p class="text-sm text-muted-foreground">
          Omit the
          <.inline_code>title</.inline_code>
          attr to render a modal with only content and a close button.
        </p>
      </.showcase_block>

      <.showcase_block title="Custom Width (class attr)" code={@code_custom_width}>
        <p class="text-sm text-muted-foreground">
          Pass
          <.inline_code>class="max-w-2xl"</.inline_code>
          to override the default
          <.inline_code>max-w-lg</.inline_code>
          width.
        </p>
      </.showcase_block>

      <.showcase_block title="Static Preview">
        <div class="relative rounded-xl border bg-black/50 p-8 flex items-center justify-center min-h-[200px]">
          <div class="relative z-10 w-full max-w-lg rounded-xl border bg-card text-card-foreground shadow-lg p-6">
            <div class="flex items-start justify-between mb-4">
              <h2 class="text-lg font-semibold leading-none tracking-tight">Example Modal</h2>
              <.button
                type="button"
                variant="ghost"
                size="icon"
                class="ml-auto -mt-1 -mr-1 h-8 w-8 text-muted-foreground"
              >
                <.icon name="hero-x-mark" class="h-4 w-4" />
              </.button>
            </div>
            <p class="text-sm text-muted-foreground">This is example modal content.</p>
            <div class="mt-4 flex justify-end gap-2">
              <.button variant="outline">Cancel</.button>
              <.button variant="primary">Confirm</.button>
            </div>
          </div>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
