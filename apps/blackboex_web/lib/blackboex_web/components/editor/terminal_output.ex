defmodule BlackboexWeb.Components.Editor.TerminalOutput do
  @moduledoc """
  A terminal-style output pane for the playground.

  Displays execution output with a dark theme, status bar,
  and appropriate styling for success/error states.
  """

  use Phoenix.Component

  import BlackboexWeb.Components.Icon

  @doc """
  Renders terminal-style output panel.
  """
  attr :output, :string, default: nil
  attr :status, :string, default: nil
  attr :duration_ms, :integer, default: nil
  attr :run_number, :integer, default: nil

  @spec terminal_output(map()) :: Phoenix.LiveView.Rendered.t()
  def terminal_output(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-zinc-900 overflow-hidden">
      <%!-- Status bar --%>
      <div class="flex items-center gap-2 h-7 px-3 shrink-0 bg-zinc-800 border-b border-zinc-700 text-2xs">
        <div :if={@status} class="flex items-center gap-1.5">
          <span class={[
            "size-2 rounded-full",
            status_color(@status)
          ]} />
          <span class="text-zinc-400 font-medium">{status_label(@status)}</span>
        </div>
        <span :if={@run_number} class="text-zinc-500 font-mono">#{@run_number}</span>
        <span :if={@duration_ms} class="text-zinc-500 font-mono tabular-nums">
          {format_duration(@duration_ms)}
        </span>
        <span :if={is_nil(@status)} class="text-zinc-500">
          <.icon name="hero-command-line-micro" class="size-3.5 inline mr-1" />Output
        </span>
      </div>

      <%!-- Output area --%>
      <div class="flex-1 overflow-auto p-4">
        <div
          :if={@status == "running"}
          class="flex items-center gap-2 text-amber-400 text-sm font-mono"
        >
          <.icon name="hero-arrow-path-micro" class="size-4 animate-spin" />
          <span>Executing...</span>
        </div>

        <pre
          :if={@output && @status != "running"}
          class={[
            "font-mono text-sm whitespace-pre-wrap break-words leading-relaxed",
            if(@status == "error", do: "text-red-400", else: "text-zinc-100")
          ]}
        >{@output}</pre>

        <p :if={is_nil(@output) && @status != "running"} class="text-zinc-500 text-sm font-mono">
          Click Run or press Cmd+Enter to execute.
        </p>
      </div>
    </div>
    """
  end

  defp status_color("success"), do: "bg-emerald-500"
  defp status_color("error"), do: "bg-red-500"
  defp status_color("running"), do: "bg-amber-500 animate-pulse"
  defp status_color(_), do: "bg-zinc-500"

  defp status_label("success"), do: "Done"
  defp status_label("error"), do: "Error"
  defp status_label("running"), do: "Running"
  defp status_label(_), do: ""

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"
end
