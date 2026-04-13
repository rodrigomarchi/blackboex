defmodule BlackboexWeb.Components.FlowEditor.ExecutionsDrawer do
  @moduledoc """
  Executions history drawer for the flow editor.
  Lists all executions for the flow and shows node-by-node detail
  when one is selected, with visual highlights pushed to the graph canvas.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Shared.CodeEditorField
  import BlackboexWeb.Components.StatusHelpers
  import BlackboexWeb.FlowLive.ExecutionHelpers

  attr :show, :boolean, default: false
  attr :executions, :list, default: []
  attr :selected_execution, :map, default: nil
  attr :expanded_exec_node, :string, default: nil
  attr :expanded, :boolean, default: false

  def executions_drawer(%{show: false} = assigns) do
    ~H"""
    """
  end

  def executions_drawer(assigns) do
    width_class = if assigns.expanded, do: "w-[70vw]", else: "w-96"
    assigns = assign(assigns, width_class: width_class)

    ~H"""
    <aside class={"flex shrink-0 flex-col border-l bg-card animate-in slide-in-from-right duration-200 #{@width_class} transition-[width] ease-in-out"}>
      <%!-- Drawer header --%>
      <div class="flex items-center justify-between border-b px-4 py-3">
        <div class="flex items-center gap-2">
          <.button
            :if={@selected_execution}
            variant="ghost-muted"
            size="icon-sm"
            phx-click="deselect_execution"
            title="Back to list"
          >
            <.icon name="hero-arrow-left" class="size-4" />
          </.button>
          <div
            :if={!@selected_execution}
            class="flex size-7 items-center justify-center rounded-lg"
            style="background: #0ea5e915; color: #0ea5e9"
          >
            <.icon name="hero-clock" class="size-3.5" />
          </div>
          <span class="text-sm font-semibold">
            {if @selected_execution, do: "Execution", else: "Executions"}
          </span>
          <span :if={@selected_execution} class="text-xs font-mono text-muted-foreground">
            {short_id(@selected_execution.id)}
          </span>
        </div>
        <div class="flex items-center gap-1">
          <.button
            variant="ghost-muted"
            size="icon-sm"
            phx-click="toggle_executions_drawer_expand"
            title={if @expanded, do: "Collapse", else: "Expand"}
          >
            <.icon
              name={if @expanded, do: "hero-arrows-pointing-in", else: "hero-arrows-pointing-out"}
              class="size-4"
            />
          </.button>
          <.button variant="ghost-muted" size="icon-sm" phx-click="close_executions_drawer">
            <.icon name="hero-x-mark" class="size-4" />
          </.button>
        </div>
      </div>

      <%!-- Drawer body --%>
      <div class="flex-1 overflow-y-auto">
        <%= if @selected_execution do %>
          <.execution_detail
            execution={@selected_execution}
            expanded_node={@expanded_exec_node}
          />
        <% else %>
          <.execution_list executions={@executions} />
        <% end %>
      </div>
    </aside>
    """
  end

  # ── Execution list ────────────────────────────────────────────────────────

  attr :executions, :list, required: true

  defp execution_list(%{executions: []} = assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-16 px-4 text-center gap-3">
      <div class="flex size-10 items-center justify-center rounded-full bg-muted">
        <.icon name="hero-clock" class="size-5 text-muted-foreground" />
      </div>
      <div class="space-y-1">
        <p class="text-sm font-medium text-muted-foreground">No executions yet</p>
        <p class="text-xs text-muted-foreground/70">Trigger the flow via webhook to see history</p>
      </div>
    </div>
    """
  end

  defp execution_list(assigns) do
    ~H"""
    <div class="divide-y">
      <button
        :for={exec <- @executions}
        type="button"
        class="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-muted/30 transition-colors text-left"
        phx-click="select_execution"
        phx-value-id={exec.id}
      >
        <div class={"size-2 rounded-full shrink-0 #{execution_status_dot(exec.status)}"} />
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-1.5">
            <span class="text-xs font-mono font-medium">{short_id(exec.id)}</span>
            <.badge variant="status" class={"gap-1 #{execution_status_classes(exec.status)}"}>
              <.icon name={status_icon(exec.status)} class="size-3" />
              {exec.status}
            </.badge>
          </div>
          <div class="text-micro text-muted-foreground mt-0.5">
            {format_time(exec.inserted_at)}
          </div>
        </div>
        <span class="text-xs font-mono text-muted-foreground shrink-0">
          {format_duration(exec.duration_ms)}
        </span>
        <.icon name="hero-chevron-right-mini" class="size-3.5 text-muted-foreground/40 shrink-0" />
      </button>
    </div>
    """
  end

  # ── Execution detail ──────────────────────────────────────────────────────

  attr :execution, :map, required: true
  attr :expanded_node, :string, default: nil

  defp execution_detail(assigns) do
    ~H"""
    <div class="p-3 space-y-3">
      <%!-- Status summary --%>
      <div class="flex flex-wrap items-center gap-1.5">
        <.badge variant="status" class={"gap-1 #{execution_status_classes(@execution.status)}"}>
          <.icon name={status_icon(@execution.status)} class="size-3" />
          {@execution.status}
        </.badge>
        <span class="text-xs font-mono text-muted-foreground">
          {format_duration(@execution.duration_ms)}
        </span>
        <span class="text-micro text-muted-foreground/70">
          {format_time(@execution.inserted_at)}
        </span>
      </div>

      <%!-- Input --%>
      <div>
        <div class="flex items-center gap-1 mb-1.5">
          <.icon name="hero-arrow-down-on-square-mini" class="size-3 text-accent-blue" />
          <span class="text-micro font-medium text-muted-foreground uppercase tracking-wide">
            Input
          </span>
        </div>
        <.code_editor_field
          id={"exec-drawer-input-#{@execution.id}"}
          value={format_json(@execution.input)}
          max_height="max-h-[120px]"
          class="w-full rounded-lg"
        />
      </div>

      <%!-- Output --%>
      <div :if={@execution.output}>
        <div class="flex items-center gap-1 mb-1.5">
          <.icon name="hero-arrow-up-on-square-mini" class="size-3 text-accent-emerald" />
          <span class="text-micro font-medium text-muted-foreground uppercase tracking-wide">
            Output
          </span>
        </div>
        <.code_editor_field
          id={"exec-drawer-output-#{@execution.id}"}
          value={format_json(@execution.output)}
          max_height="max-h-[120px]"
          class="w-full rounded-lg"
        />
      </div>

      <%!-- Node timeline --%>
      <div>
        <div class="flex items-center gap-1 mb-1.5">
          <.icon name="hero-queue-list-mini" class="size-3 text-accent-violet" />
          <span class="text-micro font-medium text-muted-foreground uppercase tracking-wide">
            Node Timeline
          </span>
        </div>
        <div class="rounded-lg border divide-y overflow-hidden">
          <div :for={ne <- @execution.node_executions}>
            <% meta = node_icon(ne.node_type) %>
            <button
              type="button"
              class={"w-full flex items-center gap-2 px-3 py-2 hover:bg-muted/30 transition-colors text-left #{if @expanded_node == ne.node_id, do: "bg-muted/20", else: ""}"}
              phx-click="toggle_exec_node"
              phx-value-node-id={ne.node_id}
            >
              <div
                class="flex size-5 shrink-0 items-center justify-center rounded"
                style={"background: #{meta.color}20; color: #{meta.color};"}
              >
                <.icon name={meta.icon} class="size-3" />
              </div>
              <span class="flex-1 text-xs font-medium truncate">{ne.node_id}</span>
              <div class={"size-1.5 rounded-full shrink-0 #{execution_status_dot(ne.status)}"} />
              <span class="text-micro font-mono text-muted-foreground w-10 text-right shrink-0">
                {format_duration(ne.duration_ms)}
              </span>
              <.icon
                name={
                  if @expanded_node == ne.node_id,
                    do: "hero-chevron-down-mini",
                    else: "hero-chevron-right-mini"
                }
                class="size-3 text-muted-foreground/40 shrink-0"
              />
            </button>
            <div :if={@expanded_node == ne.node_id} class="px-3 pb-3 pt-1 bg-muted/10 space-y-2">
              <div
                :if={ne.error}
                class="text-micro text-destructive-foreground bg-destructive/10 rounded px-2 py-1"
              >
                {ne.error}
              </div>
              <div :if={ne.input} class="space-y-1">
                <div class="flex items-center gap-1">
                  <.icon name="hero-arrow-down-on-square-mini" class="size-2.5 text-accent-blue" />
                  <span class="text-micro text-muted-foreground font-medium">Input</span>
                </div>
                <.code_editor_field
                  id={"exec-node-in-#{@execution.id}-#{ne.node_id}"}
                  value={format_json(ne.input)}
                  max_height="max-h-[120px]"
                  class="w-full rounded"
                />
              </div>
              <div :if={ne.output} class="space-y-1">
                <div class="flex items-center gap-1">
                  <.icon name="hero-arrow-up-on-square-mini" class="size-2.5 text-accent-emerald" />
                  <span class="text-micro text-muted-foreground font-medium">Output</span>
                </div>
                <.code_editor_field
                  id={"exec-node-out-#{@execution.id}-#{ne.node_id}"}
                  value={format_json(ne.output)}
                  max_height="max-h-[120px]"
                  class="w-full rounded"
                />
              </div>
              <div class="flex gap-3 text-micro text-muted-foreground/70">
                <span :if={ne.started_at}>Started: {format_time(ne.started_at)}</span>
                <span :if={ne.finished_at}>Finished: {format_time(ne.finished_at)}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  @node_type_meta %{
    "start" => %{icon: "hero-play", color: "#10b981"},
    "elixir_code" => %{icon: "hero-code-bracket", color: "#8b5cf6"},
    "condition" => %{icon: "hero-arrows-right-left", color: "#3b82f6"},
    "end" => %{icon: "hero-stop", color: "#6b7280"},
    "http_request" => %{icon: "hero-globe-alt", color: "#f97316"},
    "delay" => %{icon: "hero-clock", color: "#eab308"},
    "webhook_wait" => %{icon: "hero-arrow-path", color: "#ec4899"},
    "sub_flow" => %{icon: "hero-squares-2x2", color: "#6366f1"},
    "for_each" => %{icon: "hero-arrow-path-rounded-square", color: "#14b8a6"},
    "fail" => %{icon: "hero-x-circle", color: "#ef4444"},
    "debug" => %{icon: "hero-bug-ant", color: "#a855f7"}
  }

  defp node_icon(type),
    do: Map.get(@node_type_meta, type, %{icon: "hero-cube", color: "#6b7280"})

  defp format_json(nil), do: "—"
  defp format_json(data), do: Jason.encode!(data, pretty: true)
end
