defmodule BlackboexWeb.Components.Shared.StatCard do
  @moduledoc """
  Stat card component for displaying a labeled metric value.

  ## Examples

      <.stat_card label="Total Requests" value="12,345" />
      <.stat_card label="Error Rate" value="5.2%" color="destructive" />
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: nil
  attr :class, :string, default: nil
  attr :icon, :string, default: nil
  attr :icon_class, :string, default: nil
  attr :href, :string, default: nil

  def stat_card(assigns) do
    ~H"""
    <%= if @href do %>
      <.link
        navigate={@href}
        class={
          classes([
            "block rounded-lg border bg-card p-4 shadow-sm hover:border-primary transition-colors",
            @class
          ])
        }
      >
        <.stat_card_content
          label={@label}
          value={@value}
          color={@color}
          icon={@icon}
          icon_class={@icon_class}
        />
      </.link>
    <% else %>
      <div class={classes(["rounded-lg border bg-card p-4 shadow-sm", @class])}>
        <.stat_card_content
          label={@label}
          value={@value}
          color={@color}
          icon={@icon}
          icon_class={@icon_class}
        />
      </div>
    <% end %>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: nil
  attr :icon, :string, default: nil
  attr :icon_class, :string, default: nil

  defp stat_card_content(assigns) do
    ~H"""
    <p class={
      classes([
        "text-xs font-medium text-muted-foreground uppercase tracking-wide",
        @icon && "flex items-center gap-1"
      ])
    }>
      <.icon :if={@icon} name={@icon} class={classes(["size-3.5", @icon_class])} />
      {@label}
    </p>
    <p class={classes(["mt-1 text-2xl font-bold", @color == "destructive" && "text-destructive"])}>
      {@value}
    </p>
    """
  end
end
