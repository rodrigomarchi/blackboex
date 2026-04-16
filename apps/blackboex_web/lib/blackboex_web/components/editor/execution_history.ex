defmodule BlackboexWeb.Components.Editor.ExecutionHistory do
  @moduledoc """
  A sidebar component listing execution history for a playground.

  Displays past runs with status indicators, duration, and relative timestamps.
  Follows the same visual pattern as `PlaygroundTree`.
  """

  use Phoenix.Component

  @doc """
  Renders execution history sidebar.
  """
  attr :executions, :list, required: true
  attr :selected_execution_id, :string, default: nil

  @spec execution_history(map()) :: Phoenix.LiveView.Rendered.t()
  def execution_history(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-card border-l">
      <div class="flex items-center justify-between h-8 px-3 shrink-0 border-b">
        <span class="text-2xs font-semibold uppercase tracking-wider text-muted-foreground">
          History
        </span>
        <span class="text-2xs text-muted-foreground">{length(@executions)}</span>
      </div>
      <nav class="flex-1 overflow-y-auto py-1 text-xs" role="list">
        <.execution_entry
          :for={exec <- @executions}
          execution={exec}
          is_selected={exec.id == @selected_execution_id}
        />
        <div :if={@executions == []} class="px-3 py-4 text-center text-2xs text-muted-foreground">
          No runs yet
        </div>
      </nav>
    </div>
    """
  end

  attr :execution, :map, required: true
  attr :is_selected, :boolean, default: false

  defp execution_entry(assigns) do
    ~H"""
    <div
      class={[
        "group flex items-center gap-1.5 py-1 pr-2 pl-2 cursor-pointer select-none rounded-sm mx-1",
        if(@is_selected,
          do: "bg-accent text-accent-foreground",
          else: "text-muted-foreground hover:bg-accent/50 hover:text-foreground"
        )
      ]}
      phx-click="select_execution"
      phx-value-id={@execution.id}
    >
      <.status_dot status={@execution.status} />
      <span class="font-mono text-2xs shrink-0">#{@execution.run_number}</span>
      <span class="flex-1 truncate text-2xs">{relative_time(@execution.inserted_at)}</span>
      <span :if={@execution.duration_ms} class="text-2xs tabular-nums text-muted-foreground shrink-0">
        {format_duration(@execution.duration_ms)}
      </span>
    </div>
    """
  end

  attr :status, :string, required: true

  defp status_dot(assigns) do
    ~H"""
    <span class={[
      "size-2 rounded-full shrink-0",
      case @status do
        "success" -> "bg-emerald-500"
        "error" -> "bg-red-500"
        "running" -> "bg-amber-500 animate-pulse"
        _ -> "bg-zinc-500"
      end
    ]} />
    """
  end

  defp relative_time(nil), do: ""

  defp relative_time(datetime) do
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), datetime, :second)

    cond do
      diff < 5 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"
end
