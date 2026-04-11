defmodule BlackboexWeb.Showcase.Sections.RunModal do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  @code_initial ~S"""
  <.run_modal run_input="{}" running={false} />
  """

  @code_running ~S"""
  <.run_modal run_input="{\"user_id\": 42}" running={true} />
  """

  @code_result ~S"""
  <.run_modal
    run_input="{\"user_id\": 42}"
    running={false}
    run_result={%{output: %{status: "ok", email_sent: true}, duration_ms: 312}}
  />
  """

  @code_error ~S"""
  <.run_modal
    run_input="{\"user_id\": 42}"
    running={false}
    run_error="Execution failed: timeout after 30000ms"
  />
  """

  @run_result %{output: %{status: "ok", email_sent: true, user_id: 42}, duration_ms: 312}

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_initial, @code_initial)
      |> assign(:code_running, @code_running)
      |> assign(:code_result, @code_result)
      |> assign(:code_error, @code_error)
      |> assign(:run_result, @run_result)

    ~H"""
    <.section_header
      title="RunModal"
      description="Modal for manually running a flow with test input. Shows a JSON input editor, run button, and result/error output."
      module="BlackboexWeb.Components.FlowEditor.RunModal"
    />
    <div class="space-y-10">
      <.showcase_block title="Initial state" code={@code_initial}>
        <div class="relative h-[340px] rounded-xl border bg-card overflow-hidden shadow-inner">
          <div class="flex flex-col w-full h-full">
            <div class="flex items-center justify-between border-b px-5 py-3">
              <div class="flex items-center gap-2">
                <.icon name="hero-play" class="size-5 text-accent-emerald" />
                <span class="font-semibold text-sm">Test Run</span>
              </div>
              <.button variant="ghost-muted" size="icon-sm">
                <.icon name="hero-x-mark" class="size-5" />
              </.button>
            </div>
            <div class="flex-1 overflow-auto p-5 space-y-4">
              <p class="text-xs text-muted-foreground">
                Input (JSON) editor + Execute button rendered here.
                Trigger via <code class="font-mono bg-muted px-1 rounded">phx-click="open_run_modal"</code> in FlowHeader.
              </p>
              <.button variant="primary" size="sm">
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

      <.showcase_block title="With result" code={@code_result}>
        <div class="rounded-lg border bg-success/10 border-success/20 p-4 space-y-2">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2 text-success-foreground text-sm font-medium">
              <.icon name="hero-check-circle" class="size-4" />
              Success
            </div>
            <span class="text-2xs text-muted-foreground">312ms</span>
          </div>
          <pre class="text-xs font-mono text-muted-foreground bg-muted/50 rounded p-2 overflow-x-auto">{Jason.encode!(@run_result.output, pretty: true)}</pre>
        </div>
      </.showcase_block>

      <.showcase_block title="With error" code={@code_error}>
        <div class="rounded-lg border bg-destructive/10 border-destructive/20 p-4 space-y-2">
          <div class="flex items-center gap-2 text-destructive text-sm font-medium">
            <.icon name="hero-exclamation-circle" class="size-4" />
            Error
          </div>
          <pre class="text-xs font-mono text-destructive/80 bg-muted/50 rounded p-2">Execution failed: timeout after 30000ms</pre>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
