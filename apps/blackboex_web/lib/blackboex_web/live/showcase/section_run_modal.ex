defmodule BlackboexWeb.Showcase.Sections.RunModal do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  @code_initial ~S"""
  <.run_drawer show={true} run_input="{}" running={false} />
  """

  @code_running ~S"""
  <.run_drawer show={true} run_input="{\"user_id\": 42}" running={true} />
  """

  @code_error ~S"""
  <.run_drawer
    show={true}
    run_input="{\"user_id\": 42}"
    running={false}
    run_error="Execution failed: timeout after 30000ms"
  />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_initial, @code_initial)
      |> assign(:code_running, @code_running)
      |> assign(:code_error, @code_error)

    ~H"""
    <.section_header
      title="RunDrawer"
      description="Right-side drawer for manually running a flow with test input. Shows a JSON input editor and run button. On success navigates to ?execution=id to show results in the executions drawer."
      module="BlackboexWeb.Components.FlowEditor.RunDrawer"
    />
    <div class="space-y-10">
      <.showcase_block title="Initial state" code={@code_initial}>
        <div class="relative h-[340px] rounded-xl border bg-card overflow-hidden shadow-inner">
          <div class="flex flex-col w-full h-full">
            <div class="flex items-center justify-between border-b px-4 py-3">
              <div class="flex items-center gap-2">
                <div
                  class="flex size-7 items-center justify-center rounded-lg"
                  style="background: #10b98115; color: #10b981"
                >
                  <.icon name="hero-play" class="size-3.5" />
                </div>
                <span class="font-semibold text-sm">Test Run</span>
              </div>
              <.button variant="ghost-muted" size="icon-sm">
                <.icon name="hero-x-mark" class="size-4" />
              </.button>
            </div>
            <div class="flex-1 overflow-auto p-4 space-y-4">
              <p class="text-xs text-muted-foreground">
                Input (JSON) editor + Execute button rendered here.
                Trigger via
                <code class="font-mono bg-muted px-1 rounded">phx-click="open_run_drawer"</code>
                in FlowHeader. On success navigates to <code class="font-mono bg-muted px-1 rounded">?execution=id</code>.
              </p>
              <.button variant="primary" size="sm" class="w-full">
                <.icon name="hero-play" class="mr-1.5 size-4 text-accent-emerald" /> Execute
              </.button>
            </div>
          </div>
        </div>
      </.showcase_block>

      <.showcase_block title="Running state" code={@code_running}>
        <div class="relative h-[200px] rounded-xl border bg-card overflow-hidden shadow-inner flex items-center justify-center gap-3 text-sm text-muted-foreground">
          <.icon name="hero-arrow-path" class="size-5 animate-spin text-accent-emerald" />
          Running flow execution...
        </div>
      </.showcase_block>

      <.showcase_block title="With error" code={@code_error}>
        <div class="rounded-lg border bg-destructive/10 border-destructive/20 p-4 space-y-2">
          <div class="flex items-center gap-2 text-destructive text-sm font-medium">
            <.icon name="hero-exclamation-circle" class="size-4" /> Error
          </div>
          <pre class="text-xs font-mono text-destructive/80 bg-muted/50 rounded p-2">Execution failed: timeout after 30000ms</pre>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
