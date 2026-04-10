defmodule BlackboexWeb.ApiLive.Edit.RunLiveComponents do
  @moduledoc """
  Function components for the RunLive view.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.ApiLive.Edit.Helpers, only: [history_status_color: 1]

  # ── Test History Sidebar ───────────────────────────────────────────────

  attr :test_history, :list, required: true

  def history_sidebar(assigns) do
    ~H"""
    <div class="w-52 shrink-0 border-l pl-3 overflow-y-auto">
      <div class="flex items-center justify-between mb-2">
        <h4 class="flex items-center gap-1.5 text-xs font-semibold text-muted-foreground uppercase">
          <.icon name="hero-clock-mini" class="size-3.5 text-accent-amber" /> History
        </h4>
        <.button
          :if={@test_history != []}
          variant="ghost"
          phx-click="request_confirm"
          phx-value-action="clear_history"
          class="h-auto w-auto p-0 inline-flex items-center text-[10px] text-destructive hover:underline hover:bg-transparent"
        >
          <.icon name="hero-trash-mini" class="mr-1 size-3" /> Clear
        </.button>
      </div>

      <div class="flex flex-wrap gap-1 mb-2">
        <.button
          :for={lang <- ~w(curl python javascript elixir ruby go)}
          variant="outline"
          phx-click="copy_snippet"
          phx-value-language={lang}
          class="h-auto w-auto rounded border px-1.5 py-0.5 text-[10px] hover:bg-accent"
        >
          {lang}
        </.button>
      </div>

      <%= if @test_history == [] do %>
        <p class="text-[10px] text-muted-foreground">No requests yet</p>
      <% else %>
        <div class="space-y-1">
          <div
            :for={item <- @test_history}
            phx-click="load_history_item"
            phx-value-id={item.id}
            class="rounded border p-1.5 text-[10px] cursor-pointer hover:bg-accent"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-1">
                <span class="font-semibold">{item.method}</span>
                <span class="text-muted-foreground truncate max-w-[80px]">{item.path}</span>
              </div>
              <span class={[
                "inline-flex rounded-full px-1 py-0 text-[9px] font-semibold",
                history_status_color(item.response_status)
              ]}>
                {item.response_status}
              </span>
            </div>
            <div class="text-muted-foreground mt-0.5">{item.duration_ms}ms</div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
