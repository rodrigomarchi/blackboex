defmodule BlackboexWeb.Components.FlowEditor.RunModal do
  @moduledoc """
  Modal for executing a test run of a flow with JSON input.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Shared.CodeEditorField
  import BlackboexWeb.Components.UI.AlertBanner
  import BlackboexWeb.Components.UI.FieldLabel
  import BlackboexWeb.Components.UI.SectionHeading

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
          <.section_heading icon="hero-play" icon_class="size-5 text-accent-emerald">
            Test Run
          </.section_heading>
          <.button
            variant="ghost-muted"
            size="icon-sm"
            phx-click="close_run_modal"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </.button>
        </div>
        <div class="flex-1 overflow-auto p-5 space-y-4">
          <div>
            <.field_label>Input (JSON)</.field_label>
            <.code_editor_field
              id="code-editor-run-input"
              value={@run_input}
              readonly={false}
              event="update_run_input"
              class="w-full rounded-lg"
              height="120px"
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
              <.icon name="hero-play" class="mr-1.5 size-4 text-accent-emerald" /> Execute
            <% end %>
          </.button>

          <.alert_banner :if={@run_error} variant="destructive" icon="hero-exclamation-circle">
            <p class="text-xs font-medium mb-1">Error</p>
            <.code_editor_field
              id="flow-run-error"
              value={@run_error}
              max_height="max-h-40"
              class="mt-1"
            />
          </.alert_banner>

          <.alert_banner :if={@run_result} variant="success" icon="hero-check-circle">
            <div class="flex items-center justify-between mb-1">
              <p class="text-xs font-medium">Success</p>
              <span class="text-2xs text-muted-foreground">
                {@run_result[:duration_ms]}ms
              </span>
            </div>
            <.code_editor_field
              id="flow-run-result"
              value={Jason.encode!(@run_result[:output], pretty: true)}
              max_height="max-h-60"
            />
          </.alert_banner>
        </div>
      </div>
    </div>
    """
  end
end
