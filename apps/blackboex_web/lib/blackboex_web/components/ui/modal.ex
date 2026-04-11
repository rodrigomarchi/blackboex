defmodule BlackboexWeb.Components.Modal do
  @moduledoc """
  Modal dialog component with backdrop, close button, and keyboard support.

  ## Examples

      <.modal show={@show_modal} on_close="close_modal" title="Confirm Action">
        <p>Are you sure?</p>
      </.modal>
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Button
  import BlackboexWeb.Components.Icon

  attr :show, :boolean, required: true
  attr :on_close, :string, required: true
  attr :title, :string, default: nil
  attr :class, :string, default: nil

  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      :if={@show}
      class="fixed inset-0 z-50 flex items-center justify-center"
      phx-window-keydown={@on_close}
      phx-key="Escape"
    >
      <div
        class="absolute inset-0 bg-black/50"
        phx-click={@on_close}
      />
      <div class={
        classes([
          "relative z-10 w-full max-w-lg rounded-xl border bg-card text-card-foreground shadow-lg p-6",
          @class
        ])
      }>
        <div class="flex items-start justify-between mb-4">
          <h2 :if={@title} class="text-lg font-semibold leading-none tracking-tight">
            {@title}
          </h2>
          <.button
            type="button"
            variant="ghost"
            size="icon"
            class="ml-auto -mt-1 -mr-1 h-8 w-8 text-muted-foreground"
            phx-click={@on_close}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="h-4 w-4" />
          </.button>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
