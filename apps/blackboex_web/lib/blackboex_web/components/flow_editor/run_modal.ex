defmodule BlackboexWeb.Components.FlowEditor.RunModal do
  @moduledoc """
  Modal for executing a test run of a flow with JSON input.
  """

  use BlackboexWeb, :html

  attr :run_input, :string, required: true
  attr :running, :boolean, default: false
  attr :run_result, :any, default: nil
  attr :run_error, :any, default: nil

  def run_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div
        class="flex flex-col w-[600px] max-h-[80vh] rounded-xl border bg-card shadow-2xl"
        phx-click-away="close_run_modal"
      >
        <div class="flex items-center justify-between border-b px-5 py-3">
          <div class="flex items-center gap-2">
            <.icon name="hero-play" class="size-5 text-green-500" />
            <h2 class="text-sm font-semibold">Test Run</h2>
          </div>
          <button
            phx-click="close_run_modal"
            class="rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <div class="flex-1 overflow-auto p-5 space-y-4">
          <div>
            <label class="block text-xs font-medium text-muted-foreground mb-1.5">
              Input (JSON)
            </label>
            <div
              id="code-editor-run-input"
              phx-hook="CodeEditor"
              phx-update="ignore"
              data-language="json"
              data-event="update_run_input"
              data-value={@run_input}
              class="w-full rounded-lg border overflow-hidden"
              style="height: 120px;"
            />
          </div>
          <.button
            variant="primary"
            size="sm"
            phx-click="execute_test_run"
            disabled={@running}
          >
            <%= if @running do %>
              <.icon name="hero-arrow-path" class="mr-1.5 size-4 animate-spin" /> Running...
            <% else %>
              <.icon name="hero-play" class="mr-1.5 size-4 text-green-400" /> Execute
            <% end %>
          </.button>

          <%= if @run_error do %>
            <div class="rounded-lg border border-destructive/50 bg-destructive/5 p-3">
              <p class="text-xs font-medium text-destructive">Error</p>
              <div
                id="flow-run-error"
                phx-hook="CodeEditor"
                data-language="json"
                data-readonly="true"
                data-minimal="true"
                data-value={@run_error}
                class="mt-1 rounded overflow-hidden [&_.cm-editor]:max-h-40"
                phx-update="ignore"
              >
              </div>
            </div>
          <% end %>

          <%= if @run_result do %>
            <div class="rounded-lg border border-green-500/50 bg-green-500/5 p-3 space-y-2">
              <div class="flex items-center justify-between">
                <p class="text-xs font-medium text-green-600">Success</p>
                <span class="text-[0.65rem] text-muted-foreground">
                  {@run_result[:duration_ms]}ms
                </span>
              </div>
              <div
                id="flow-run-result"
                phx-hook="CodeEditor"
                data-language="json"
                data-readonly="true"
                data-minimal="true"
                data-value={Jason.encode!(@run_result[:output], pretty: true)}
                class="rounded overflow-hidden [&_.cm-editor]:max-h-60"
                phx-update="ignore"
              >
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
