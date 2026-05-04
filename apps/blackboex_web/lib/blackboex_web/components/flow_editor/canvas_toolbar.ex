defmodule BlackboexWeb.Components.FlowEditor.CanvasToolbar do
  @moduledoc """
  Floating toolbar for Drawflow canvas controls.
  Rendered as a static overlay — JS hook binds click events.
  """

  use BlackboexWeb, :html

  @spec canvas_toolbar(map()) :: Phoenix.LiveView.Rendered.t()
  def canvas_toolbar(assigns) do
    ~H"""
    <div
      id="df-canvas-toolbar"
      phx-update="ignore"
      class="absolute bottom-4 left-[50%] -translate-x-[50%] z-50 flex items-center gap-0.5 rounded-xl border border-border bg-card px-1 py-1 shadow-lg pointer-events-auto"
    >
      <div class="flex items-center gap-0.5">
        <button
          type="button"
          class="flex items-center justify-center size-8 rounded-lg bg-transparent text-muted-foreground hover:bg-muted hover:text-foreground active:bg-accent transition-colors cursor-pointer"
          data-action="zoom-in"
          title="Zoom in"
        >
          <.icon name="hero-plus" class="size-4" />
        </button>
        <span
          class="text-2xs font-semibold font-mono text-muted-foreground min-w-[40px] text-center select-none"
          data-zoom-label
        >
          100%
        </span>
        <button
          type="button"
          class="flex items-center justify-center size-8 rounded-lg bg-transparent text-muted-foreground hover:bg-muted hover:text-foreground active:bg-accent transition-colors cursor-pointer"
          data-action="zoom-out"
          title="Zoom out"
        >
          <.icon name="hero-minus" class="size-4" />
        </button>
      </div>
      <div class="w-px h-5 bg-border mx-0.5"></div>
      <div class="flex items-center gap-0.5">
        <button
          type="button"
          class="flex items-center justify-center size-8 rounded-lg bg-transparent text-muted-foreground hover:bg-muted hover:text-foreground active:bg-accent transition-colors cursor-pointer"
          data-action="zoom-reset"
          title="Reset zoom"
        >
          <.icon name="hero-arrow-path" class="size-4" />
        </button>
        <button
          type="button"
          class="flex items-center justify-center size-8 rounded-lg bg-transparent text-muted-foreground hover:bg-muted hover:text-foreground active:bg-accent transition-colors cursor-pointer"
          data-action="fit-view"
          title="Fit to screen"
        >
          <.icon name="hero-viewfinder-circle" class="size-4" />
        </button>
      </div>
      <div class="w-px h-5 bg-border mx-0.5"></div>
      <div class="flex items-center gap-0.5">
        <button
          type="button"
          class="flex items-center justify-center size-8 rounded-lg bg-transparent text-muted-foreground hover:bg-muted hover:text-foreground active:bg-accent transition-colors cursor-pointer"
          data-action="auto-layout"
          title="Auto layout"
        >
          <.icon name="hero-squares-2x2" class="size-4" />
        </button>
        <button
          type="button"
          class="flex items-center justify-center size-8 rounded-lg bg-transparent text-muted-foreground hover:bg-muted hover:text-foreground active:bg-accent transition-colors cursor-pointer"
          data-action="toggle-lock"
          title="Toggle lock (edit/view)"
          data-lock-btn
        >
          <span data-lock-icon><.icon name="hero-lock-open" class="size-4" /></span>
        </button>
      </div>
    </div>
    """
  end
end
