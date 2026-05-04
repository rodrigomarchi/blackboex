defmodule BlackboexWeb.Components.Card do
  @moduledoc """
  Implement of card components from https://ui.shadcn.com/docs/components/card
  """
  use BlackboexWeb.Component

  @doc """
  Card component

  ## Examples:

        <.card>
          <.card_header>
            <.card_title>Card title</.card_title>
            <.card_description>Card subtitle</.card_description>
          </.card_header>
          <.card_content>
            Card text
          </.card_content>
          <.card_footer>
            <.button>Button</.button>
          </.card_footer>
        </.card>
  """

  attr :class, :string, default: nil
  slot :inner_block, required: true
  attr :rest, :global

  def card(assigns) do
    ~H"""
    <div class={classes(["rounded-xl border bg-card text-card-foreground shadow", @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :size, :string, values: ~w(default compact), default: "default"
  slot :inner_block, required: true
  attr :rest, :global

  def card_header(assigns) do
    size_class = if assigns.size == "compact", do: "px-4 py-2.5", else: "p-6"
    assigns = assign(assigns, :size_class, size_class)

    ~H"""
    <div class={classes(["flex flex-col space-y-1.5", @size_class, @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :size, :string, values: ~w(default label), default: "default"
  slot :inner_block, required: true
  attr :rest, :global

  def card_title(assigns) do
    size_class =
      if assigns.size == "label",
        do: "text-xs font-medium text-muted-foreground uppercase tracking-wider",
        else: "text-lg font-semibold leading-none tracking-tight"

    assigns = assign(assigns, :size_class, size_class)

    ~H"""
    <h3 class={classes([@size_class, @class])} {@rest}>
      {render_slot(@inner_block)}
    </h3>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true
  attr :rest, :global

  def card_description(assigns) do
    ~H"""
    <p class={classes(["text-sm text-muted-foreground", @class])} {@rest}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :class, :string, default: nil

  attr :standalone, :boolean,
    default: false,
    doc: "true when used without card_header (restores top padding)"

  attr :size, :string, values: ~w(default compact), default: "default"
  slot :inner_block, required: true
  attr :rest, :global

  def card_content(assigns) do
    padding =
      case {assigns.standalone, assigns.size} do
        {true, _} -> "p-6"
        {false, "compact"} -> "px-4 pb-3 pt-0"
        {false, "default"} -> "p-6 pt-0"
      end

    assigns = assign(assigns, :padding, padding)

    ~H"""
    <div class={classes([@padding, @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true
  attr :rest, :global

  def card_footer(assigns) do
    ~H"""
    <div class={classes(["flex items-center justify-between p-6 pt-0 ", @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
