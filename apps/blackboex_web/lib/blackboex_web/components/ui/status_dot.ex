defmodule BlackboexWeb.Components.UI.StatusDot do
  @moduledoc """
  Colored pill with leading dot for status displays (active/draft/running/etc).

  Replaces the repeated `<span class="rounded-full bg-*">` + nested dot pattern.
  The status is matched against a small palette; unknown values fall back to
  neutral muted styling. Override with an explicit `tone` to force a palette.

  ## Examples

      <.status_dot status="active" />
      <.status_dot status="draft" />
      <.status_dot status="running" label="In progress" pulse />
  """
  use BlackboexWeb.Component

  @tones %{
    "active" =>
      {"bg-status-completed/15 text-status-completed-foreground", "bg-status-completed"},
    "running" => {"bg-status-running/15 text-status-running-foreground", "bg-status-running"},
    "pending" => {"bg-status-pending/15 text-status-pending-foreground", "bg-status-pending"},
    "draft" => {"bg-muted text-muted-foreground", "bg-muted-foreground"},
    "paused" => {"bg-status-halted/15 text-status-halted-foreground", "bg-status-halted"},
    "failed" => {"bg-status-failed/15 text-status-failed-foreground", "bg-status-failed"},
    "error" => {"bg-status-failed/15 text-status-failed-foreground", "bg-status-failed"},
    "archived" => {"bg-muted text-muted-foreground", "bg-muted-foreground"},
    "success" =>
      {"bg-status-completed/15 text-status-completed-foreground", "bg-status-completed"},
    "completed" =>
      {"bg-status-completed/15 text-status-completed-foreground", "bg-status-completed"}
  }

  @fallback_tone {"bg-muted text-muted-foreground", "bg-muted-foreground"}

  attr :status, :string, required: true
  attr :label, :string, default: nil
  attr :tone, :string, default: nil
  attr :pulse, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global

  @spec status_dot(map()) :: Phoenix.LiveView.Rendered.t()
  def status_dot(assigns) do
    key = assigns.tone || assigns.status
    {pill, dot} = Map.get(@tones, key, @fallback_tone)

    assigns =
      assigns
      |> assign(:pill_class, pill)
      |> assign(:dot_class, dot)

    ~H"""
    <span
      class={
        classes([
          "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium",
          @pill_class,
          @class
        ])
      }
      {@rest}
    >
      <span class={classes(["size-1.5 rounded-full", @dot_class, @pulse && "animate-pulse"])} />
      {@label || @status}
    </span>
    """
  end
end
