defmodule BlackboexWeb.Components.FlowEditor.RunDrawer do
  @moduledoc """
  Right-side drawer for executing a test run of a flow with JSON input.

  Replaces the previous modal approach. On successful execution the caller
  navigates to `?execution=<id>` so the result is shown in the executions drawer.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Shared.CodeEditorField
  import BlackboexWeb.Components.UI.AlertBanner
  import BlackboexWeb.Components.UI.FieldLabel

  attr :show, :boolean, default: false
  attr :run_input, :string, required: true
  attr :running, :boolean, default: false
  attr :run_error, :any, default: nil

  def run_drawer(%{show: false} = assigns) do
    ~H"""
    """
  end

  def run_drawer(assigns) do
    ~H"""
    <aside class="flex w-96 shrink-0 flex-col border-l bg-card animate-in slide-in-from-right duration-200">
      <%!-- Drawer header --%>
      <div class="flex items-center justify-between border-b px-4 py-3">
        <div class="flex items-center gap-2">
          <div
            class="flex size-7 items-center justify-center rounded-lg"
            style="background: #10b98115; color: #10b981"
          >
            <.icon name="hero-play" class="size-3.5" />
          </div>
          <span class="text-sm font-semibold">Test Run</span>
        </div>
        <.button variant="ghost-muted" size="icon-sm" phx-click="close_run_drawer">
          <.icon name="hero-x-mark" class="size-4" />
        </.button>
      </div>

      <%!-- Drawer body --%>
      <div class="flex-1 overflow-y-auto p-4 space-y-4">
        <div>
          <.field_label>Input (JSON)</.field_label>
          <.code_editor_field
            id="run-drawer-input"
            value={@run_input}
            readonly={false}
            event="update_run_input"
            class="w-full rounded-lg"
            height="200px"
          />
        </div>

        <.button
          variant="primary"
          size="sm"
          phx-click="execute_test_run"
          disabled={@running}
          class="w-full"
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
            id="run-drawer-error"
            value={@run_error}
            max_height="max-h-40"
            class="mt-1"
          />
        </.alert_banner>
      </div>
    </aside>
    """
  end
end
