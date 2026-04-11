defmodule BlackboexWeb.Components.UI.AlertBanner do
  @moduledoc """
  Contextual feedback banner for inline alerts (error, warning, info, success).

  ## Examples

      <.alert_banner variant="destructive">Something went wrong</.alert_banner>
      <.alert_banner variant="warning" icon="hero-exclamation-triangle">
        This action cannot be undone.
      </.alert_banner>
      <.alert_banner variant="success">Operation completed successfully</.alert_banner>
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon

  @variants %{
    "destructive" => "border-destructive/50 bg-destructive/5 text-destructive",
    "warning" => "border-warning/50 bg-warning/10 text-warning-foreground",
    "info" => "border-info/50 bg-info/10 text-info-foreground",
    "success" => "border-success/50 bg-success/5 text-success-foreground"
  }

  attr :variant, :string, values: ~w(destructive warning info success), default: "info"
  attr :icon, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  @spec alert_banner(map()) :: Phoenix.LiveView.Rendered.t()
  def alert_banner(assigns) do
    assigns = assign(assigns, :variant_class, @variants[assigns.variant])

    ~H"""
    <div
      class={
        classes([
          "rounded-lg border p-3 text-sm",
          @variant_class,
          @class
        ])
      }
      {@rest}
    >
      <div class={if @icon, do: "flex items-start gap-2", else: nil}>
        <.icon :if={@icon} name={@icon} class="size-4 shrink-0 mt-0.5" />
        <div>{render_slot(@inner_block)}</div>
      </div>
    </div>
    """
  end
end
