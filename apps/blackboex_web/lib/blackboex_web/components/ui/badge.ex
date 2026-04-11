defmodule BlackboexWeb.Components.Badge do
  @moduledoc false
  use BlackboexWeb.Component

  @doc """
  Renders a badge component.

  ## Examples

      <.badge>Badge</.badge>
      <.badge variant="destructive">Badge</.badge>
      <.badge variant="status" class={execution_status_classes("completed")}>completed</.badge>
      <.badge size="xs" variant="status" class="bg-destructive/10 text-destructive">3</.badge>
  """
  attr :class, :string, default: nil

  attr :variant, :string,
    values: ~w(default secondary destructive outline status),
    default: "default",
    doc: "the badge variant style"

  attr :size, :string,
    values: ~w(default xs),
    default: "default",
    doc: "badge size"

  attr :rest, :global
  slot :inner_block, required: true

  @base "inline-flex items-center rounded-full font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"

  @variants %{
    "default" =>
      "border border-transparent bg-primary text-primary-foreground hover:bg-primary/80",
    "secondary" =>
      "border border-transparent bg-secondary text-secondary-foreground hover:bg-secondary/80",
    "destructive" =>
      "border border-transparent bg-destructive text-destructive-foreground hover:bg-destructive/80",
    "outline" => "border text-foreground",
    "status" => "border-transparent"
  }

  @sizes %{
    "default" => "px-2.5 py-0.5 text-xs",
    "xs" => "px-1.5 text-2xs"
  }

  @spec badge(map()) :: Phoenix.LiveView.Rendered.t()
  def badge(assigns) do
    assigns =
      assign(
        assigns,
        :computed_class,
        classes([
          @base,
          @variants[assigns.variant],
          @sizes[assigns.size],
          assigns.class
        ])
      )

    ~H"""
    <div class={@computed_class} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
