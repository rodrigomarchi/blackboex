defmodule BlackboexWeb.Components.Shared.Page do
  @moduledoc """
  Layout primitives for normal content pages (app layout).

  `.page_header/1` is the single unified header bar for the entire platform —
  same visual as editor toolbars (h-12, border-b, bg-card). Supports two modes:

    * Content pages: pass `icon` + `title` (no back navigation)
    * Editor pages: pass `back_path` + `title` (shows back arrow instead of icon)

  `.page/1` is the scrollable content area below the header — owns padding,
  max-width, and vertical spacing.

  `.page_section/1` is a lightweight grouping element for subsections.

  ## Content page example

      <.page_header icon="hero-bolt" icon_class="text-accent-amber" title="APIs">
        <:actions>
          <.button variant="primary">Create API</.button>
        </:actions>
      </.page_header>
      <.page>
        <.card>...</.card>
      </.page>

  ## Editor page example

      <.page_header back_path={~p"/pages"} back_label="Pages" title={@page.title}>
        <:badge><.badge variant="secondary">draft</.badge></:badge>
        <:actions>
          <.button phx-click="save">Save</.button>
        </:actions>
      </.page_header>
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon

  attr :title, :string, required: true
  attr :back_path, :string, default: nil
  attr :back_label, :string, default: "Back"
  attr :icon, :string, default: nil
  attr :icon_class, :string, default: nil
  attr :class, :any, default: nil

  slot :badge
  slot :actions

  @spec page_header(map()) :: Phoenix.LiveView.Rendered.t()
  def page_header(assigns) do
    ~H"""
    <header class={classes(["flex h-12 shrink-0 items-center border-b bg-card px-4 gap-3", @class])}>
      <.link
        :if={@back_path}
        navigate={@back_path}
        class="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-accent"
        title={@back_label}
      >
        <.icon name="hero-arrow-left" class="size-4" />
      </.link>

      <.icon :if={@icon && !@back_path} name={@icon} class={["size-4 shrink-0", @icon_class]} />

      <h1 class="text-sm font-semibold truncate">{@title}</h1>

      {render_slot(@badge)}

      <div class="flex-1" />

      <div :if={@actions != []} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec page(map()) :: Phoenix.LiveView.Rendered.t()
  def page(assigns) do
    ~H"""
    <div class={classes(["flex-1 overflow-y-auto", @class])} {@rest}>
      <div class="mx-auto max-w-6xl px-4 py-6 md:px-6 md:py-8 space-y-6">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :spacing, :string, values: ~w(tight default loose), default: "default"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec page_section(map()) :: Phoenix.LiveView.Rendered.t()
  def page_section(assigns) do
    ~H"""
    <section class={classes([spacing_class(@spacing), @class])} {@rest}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp spacing_class("tight"), do: "space-y-3"
  defp spacing_class("default"), do: "space-y-4"
  defp spacing_class("loose"), do: "space-y-6"
end
