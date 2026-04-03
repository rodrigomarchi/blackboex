defmodule BlackboexWeb.Components.Editor.RightPanel do
  @moduledoc """
  Right panel shell for Chat or Config modes.
  Content is provided via the inner_block slot by the parent.
  """
  use BlackboexWeb, :html

  attr :mode, :atom, required: true
  slot :inner_block, required: true

  @spec right_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def right_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full w-[340px] shrink-0 border-l bg-card overflow-hidden">
      <div class="flex items-center justify-between border-b px-3 py-2 shrink-0">
        <h2 class="text-sm font-semibold">
          {if @mode == :chat, do: "Chat", else: "Settings"}
        </h2>
        <button
          phx-click={if @mode == :chat, do: "toggle_chat", else: "toggle_config"}
          class="p-1 text-muted-foreground hover:text-foreground rounded hover:bg-accent"
          title="Close (Esc)"
        >
          <.icon name="hero-x-mark" class="size-3.5" />
        </button>
      </div>

      <div class="flex-1 overflow-hidden">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
