defmodule BlackboexWeb.Components.Button do
  @moduledoc """
  Button component with variant/size support and navigation integration.

  Renders a `<button>` by default, or a `<.link>` when `navigate`, `patch`, or `href` is provided.

  ## Examples

      <.button>Click me</.button>
      <.button variant="primary" phx-click="go">Submit</.button>
      <.button variant="outline" size="sm">Cancel</.button>
      <.button navigate={~p"/home"}>Home</.button>
  """
  use BlackboexWeb.Component

  @base "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50"

  @variants %{
    "default" => "border border-input bg-background hover:bg-accent hover:text-accent-foreground",
    "primary" => "bg-primary text-primary-foreground hover:bg-primary/90",
    "secondary" => "bg-secondary text-secondary-foreground hover:bg-secondary/80",
    "destructive" => "bg-destructive text-destructive-foreground hover:bg-destructive/90",
    "outline" => "border border-input bg-background hover:bg-accent hover:text-accent-foreground",
    "ghost" => "hover:bg-accent hover:text-accent-foreground",
    "link" => "text-primary underline-offset-4 hover:underline"
  }

  @sizes %{
    "default" => "h-10 px-4 py-2",
    "sm" => "h-9 rounded-md px-3",
    "lg" => "h-11 rounded-md px-8",
    "icon" => "h-10 w-10"
  }

  attr :type, :string, default: nil
  attr :class, :any, default: nil

  attr :variant, :string,
    values: ~w(default primary secondary destructive outline ghost link),
    default: "default"

  attr :size, :string, values: ~w(default sm lg icon), default: "default"
  attr :rest, :global, include: ~w(href navigate patch method download disabled form name value)

  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :computed_class,
        classes([
          @base,
          @variants[assigns.variant],
          @sizes[assigns.size],
          assigns.class
        ])
      )

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@computed_class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button type={@type} class={@computed_class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end
end
