defmodule BlackboexWeb.Components.Flash do
  @moduledoc """
  Toast-style flash notification component.
  """
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Icon
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={
        JS.push("lv:clear-flash", value: %{key: @kind})
        |> BlackboexWeb.Components.Helpers.hide("##{@id}")
      }
      role="alert"
      class="fixed top-4 right-4 z-[200]"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 w-80 sm:w-96 rounded-lg border px-4 py-3 text-sm shadow-lg",
        @kind == :info && "border-border bg-background text-foreground",
        @kind == :error && "border-destructive/50 bg-destructive text-destructive-foreground"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0 mt-0.5 text-blue-400" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0 mt-0.5 text-red-400" />
        <div class="flex-1 text-wrap">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <button type="button" class="group self-start cursor-pointer" aria-label="close">
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end
end
