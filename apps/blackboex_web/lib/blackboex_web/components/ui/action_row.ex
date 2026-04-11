defmodule BlackboexWeb.Components.UI.ActionRow do
  @moduledoc """
  Horizontal row with a title, description, and a trailing action (typically a button).

  Used for danger-zone and settings-style rows where a labeled description sits
  opposite a single action control. The `destructive` variant emphasizes
  irreversible operations with a red border.

  ## Examples

      <.action_row variant="destructive">
        <:title>Archive this API</:title>
        <:description>Removes from active list.</:description>
        <:action>
          <.button variant="outline" size="sm">Archive API</.button>
        </:action>
      </.action_row>
  """
  use BlackboexWeb.Component

  @variants %{
    "default" => "border-border",
    "destructive" => "border-destructive/30"
  }

  attr :variant, :string, values: ~w(default destructive), default: "default"
  attr :class, :any, default: nil
  attr :rest, :global

  slot :title, required: true
  slot :description
  slot :action, required: true

  @spec action_row(map()) :: Phoenix.LiveView.Rendered.t()
  def action_row(assigns) do
    assigns = assign(assigns, :variant_class, @variants[assigns.variant])

    ~H"""
    <div
      class={
        classes([
          "rounded-lg border p-4 flex items-center justify-between gap-4",
          @variant_class,
          @class
        ])
      }
      {@rest}
    >
      <div class="min-w-0">
        <p class="text-sm font-medium">{render_slot(@title)}</p>
        <p :if={@description != []} class="text-muted-caption">
          {render_slot(@description)}
        </p>
      </div>
      <div class="shrink-0">{render_slot(@action)}</div>
    </div>
    """
  end
end
