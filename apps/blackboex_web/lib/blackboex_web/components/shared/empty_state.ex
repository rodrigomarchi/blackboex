defmodule BlackboexWeb.Components.Shared.EmptyState do
  @moduledoc """
  Empty state component with optional icon, title, description, and actions.

  ## Examples

      <.empty_state icon="hero-inbox" title="No APIs yet" description="Create your first API to get started.">
        <:actions>
          <.button variant="primary" navigate={~p"/apis/new"}>New API</.button>
        </:actions>
      </.empty_state>
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon
  import BlackboexWeb.Components.UI.SectionHeading

  attr :icon, :string, default: nil
  attr :icon_class, :string, default: "text-muted-foreground/60"
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :class, :string, default: nil

  slot :actions

  def empty_state(assigns) do
    ~H"""
    <div class={
      classes([
        "flex flex-col items-center justify-center rounded-xl border bg-card text-card-foreground p-12 text-center",
        @class
      ])
    }>
      <div :if={@icon} class="mb-4">
        <.icon name={@icon} class={classes(["size-12", @icon_class])} />
      </div>
      <.section_heading level="h1" compact>
        {@title}
      </.section_heading>
      <p :if={@description} class="mt-2 text-sm text-muted-foreground max-w-sm">
        {@description}
      </p>
      <div :if={@actions != []} class="mt-6">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end
end
