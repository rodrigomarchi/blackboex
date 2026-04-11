defmodule BlackboexWeb.Components.Shared.ModeToggle do
  @moduledoc """
  Segmented toggle bar for switching between 2 modes (e.g. template/blank, template/describe).

  Options are `{value, label, icon}` tuples. When `click_event` is set, all buttons emit that
  event with `phx-value-mode={value}`. When `click_event` is nil, each option's `value` is used
  as its own click event name directly.
  """

  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon
  import BlackboexWeb.Components.Button

  attr :options, :list, required: true, doc: "List of {value, label, icon} tuples"
  attr :active, :any, required: true, doc: "Currently active value"
  attr :click_event, :string, default: nil, doc: "Shared event name (nil = per-option events)"
  attr :class, :string, default: nil

  @spec mode_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def mode_toggle(assigns) do
    ~H"""
    <div class={classes(["flex gap-1 rounded-lg bg-muted p-1", @class])}>
      <.button
        :for={{value, label, icon} <- @options}
        type="button"
        variant="ghost"
        phx-click={@click_event || value}
        phx-value-mode={@click_event && value}
        class={[
          "h-auto flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors hover:bg-transparent",
          if(to_string(@active) == to_string(value),
            do: "bg-background text-foreground shadow-sm",
            else: "text-muted-foreground hover:text-foreground"
          )
        ]}
      >
        <.icon name={icon} class="mr-1.5 size-4 inline" /> {label}
      </.button>
    </div>
    """
  end
end
