defmodule BlackboexWeb.Showcase.Sections.FlashShowcase do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  @code_info ~S"""
  <.flash kind={:info} title="Success" flash={%{"info" => "Your changes have been saved."}}>
  </.flash>
  """

  @code_error ~S"""
  <.flash kind={:error} title="Error" flash={%{"error" => "Something went wrong. Please try again."}}>
  </.flash>
  """

  @code_no_title ~S"""
  <.flash kind={:info} flash={%{"info" => "Operation completed successfully."}}>
  </.flash>
  """

  @code_custom_id ~S"""
  <.flash id="my-custom-flash" kind={:info} flash={%{"info" => "Custom id flash message."}} />
  """

  @code_liveview_usage ~S"""
  # In your LiveView handle_event or mount:
  socket = put_flash(socket, :info, "Changes saved successfully.")
  socket = put_flash(socket, :error, "Failed to save changes.")

  # Clear a specific flash:
  socket = clear_flash(socket, :info)

  # In your template (flash_group is rendered automatically by the layout):
  # flash_group/1 in layouts.ex handles both :info and :error flashes.
  # You can also render individual flashes manually:
  <.flash kind={:info} flash={@flash} />
  <.flash kind={:error} flash={@flash} />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_info, @code_info)
      |> assign(:code_error, @code_error)
      |> assign(:code_no_title, @code_no_title)
      |> assign(:code_custom_id, @code_custom_id)
      |> assign(:code_liveview_usage, @code_liveview_usage)

    ~H"""
    <.section_header
      title="Flash"
      description="Toast notification component. kind=:info renders a blue/info flash, kind=:error renders a red/error flash. Managed by the LiveView flash system via put_flash/3. The flash_group/1 from Layouts renders all flashes automatically."
      module="BlackboexWeb.Components.Flash"
    />
    <div class="space-y-10">
      <.showcase_block title="Info flash" code={@code_info}>
        <div class="relative min-h-[80px] flex items-start">
          <div class="flex items-start gap-3 w-80 sm:w-96 rounded-lg border border-border bg-background text-foreground px-4 py-3 text-sm shadow-lg">
            <.icon name="hero-information-circle" class="size-5 shrink-0 mt-0.5 text-accent-blue" />
            <div class="flex-1 text-wrap">
              <p class="font-semibold">Success</p>
              <p>Your changes have been saved.</p>
            </div>
            <button type="button" class="group self-start cursor-pointer" aria-label="close">
              <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
            </button>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Error flash" code={@code_error}>
        <div class="relative min-h-[80px] flex items-start">
          <div class="flex items-start gap-3 w-80 sm:w-96 rounded-lg border border-destructive/50 bg-destructive text-destructive-foreground px-4 py-3 text-sm shadow-lg">
            <.icon
              name="hero-exclamation-circle"
              class="size-5 shrink-0 mt-0.5 text-destructive-foreground"
            />
            <div class="flex-1 text-wrap">
              <p class="font-semibold">Error</p>
              <p>Something went wrong. Please try again.</p>
            </div>
            <button type="button" class="group self-start cursor-pointer" aria-label="close">
              <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
            </button>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Without title" code={@code_no_title}>
        <div class="relative min-h-[70px] flex items-start">
          <div class="flex items-start gap-3 w-80 sm:w-96 rounded-lg border border-border bg-background text-foreground px-4 py-3 text-sm shadow-lg">
            <.icon name="hero-information-circle" class="size-5 shrink-0 mt-0.5 text-accent-blue" />
            <div class="flex-1 text-wrap">
              <p>Operation completed successfully.</p>
            </div>
            <button type="button" class="group self-start cursor-pointer" aria-label="close">
              <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
            </button>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="With custom id" code={@code_custom_id}>
        <p class="text-sm text-muted-foreground">
          Pass <code class="font-mono text-xs bg-muted px-1 rounded">id=</code>
          to target the flash element with JS commands (e.g.
          <code class="font-mono text-xs bg-muted px-1 rounded">JS.hide("#my-custom-flash")</code>).
          Defaults to <code class="font-mono text-xs bg-muted px-1 rounded">flash-:kind</code>.
        </p>
      </.showcase_block>

      <.showcase_block title="Usage in LiveView (code)" code={@code_liveview_usage}>
        <p class="text-sm text-muted-foreground">
          Use <code class="font-mono text-xs bg-muted px-1 rounded">put_flash/3</code>
          and <code class="font-mono text-xs bg-muted px-1 rounded">clear_flash/2</code>
          in your LiveView. The layout's
          <code class="font-mono text-xs bg-muted px-1 rounded">flash_group</code>
          renders both flash kinds automatically on every page.
        </p>
      </.showcase_block>
    </div>
    """
  end
end
