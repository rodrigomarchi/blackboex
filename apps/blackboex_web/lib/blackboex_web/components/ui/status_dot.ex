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
    "active" => {"bg-green-500/15 text-green-600", "bg-green-500"},
    "running" => {"bg-blue-500/15 text-blue-600", "bg-blue-500"},
    "pending" => {"bg-amber-500/15 text-amber-600", "bg-amber-500"},
    "draft" => {"bg-muted text-muted-foreground", "bg-muted-foreground"},
    "paused" => {"bg-amber-500/15 text-amber-600", "bg-amber-500"},
    "failed" => {"bg-red-500/15 text-red-600", "bg-red-500"},
    "error" => {"bg-red-500/15 text-red-600", "bg-red-500"},
    "archived" => {"bg-muted text-muted-foreground", "bg-muted-foreground"},
    "success" => {"bg-green-500/15 text-green-600", "bg-green-500"},
    "completed" => {"bg-green-500/15 text-green-600", "bg-green-500"}
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
