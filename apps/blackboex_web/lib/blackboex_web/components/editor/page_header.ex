defmodule BlackboexWeb.Components.Editor.PageHeader do
  @moduledoc """
  Generic header toolbar for editor pages (Pages, Playgrounds, etc.).

  Compact bar with back navigation, title, optional badge, and action buttons.
  Follows the same visual pattern as `editor_toolbar` but without API-specific attrs.

  ## Examples

      <.editor_page_header
        title={@page.title}
        back_path={project_path(@current_scope, "/pages")}
        back_label="Pages"
      >
        <:badge>
          <.badge variant="secondary">draft</.badge>
        </:badge>
        <:actions>
          <.button phx-click="save">Save</.button>
        </:actions>
      </.editor_page_header>
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon

  attr :title, :string, required: true
  attr :back_path, :string, required: true
  attr :back_label, :string, default: "Back"
  attr :class, :any, default: nil

  slot :badge
  slot :actions

  @spec editor_page_header(map()) :: Phoenix.LiveView.Rendered.t()
  def editor_page_header(assigns) do
    ~H"""
    <header class={classes(["flex h-11 shrink-0 items-center border-b bg-card px-3 gap-2", @class])}>
      <.link
        navigate={@back_path}
        class="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-accent"
        title={@back_label}
      >
        <.icon name="hero-arrow-left" class="size-4" />
      </.link>

      <div class="h-4 w-px bg-border" />

      <h1 class="text-sm font-semibold truncate max-w-[300px]">{@title}</h1>

      {render_slot(@badge)}

      <div class="flex-1" />

      <div :if={@actions != []} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end
end
