defmodule BlackboexWeb.Components.UI.SectionHeading do
  @moduledoc """
  Semantic section heading component for in-page titles and subsections.

  Replaces the repeated `<h2>`/`<h3>` + optional icon + description pattern.

  ## Examples

      <.section_heading>Section Title</.section_heading>
      <.section_heading level="h3">Subsection</.section_heading>
      <.section_heading icon="hero-cog-6-tooth">Settings</.section_heading>
      <.section_heading>
        API Keys
        <:description>Manage access tokens for this API.</:description>
      </.section_heading>
  """
  use BlackboexWeb.Component

  alias BlackboexWeb.Components.Icon

  @base_classes %{
    "h1" => "text-lg font-semibold leading-8 text-foreground",
    "h2" => "text-sm font-semibold text-foreground",
    "h3" => "text-xs font-medium text-muted-foreground"
  }

  attr :level, :string, values: ~w(h1 h2 h3), default: "h2"
  attr :icon, :string, default: nil
  attr :icon_class, :string, default: "size-4 text-muted-foreground"
  attr :compact, :boolean, default: false, doc: "removes gap between heading and wrapper"

  attr :variant, :string,
    values: ~w(default label),
    default: "default",
    doc: "label variant adds uppercase tracking and bottom margin (for sidebar sections)"

  attr :class, :any, default: nil
  attr :heading_class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true
  slot :description

  @spec section_heading(map()) :: Phoenix.LiveView.Rendered.t()
  def section_heading(assigns) do
    assigns =
      assigns
      |> assign(:base_class, @base_classes[assigns.level])
      |> assign(:is_label, assigns.variant == "label")

    ~H"""
    <div
      class={
        classes([
          "flex flex-col",
          if(@compact, do: "gap-0", else: "gap-1"),
          @is_label && "uppercase tracking-wider mb-3",
          @class
        ])
      }
      {@rest}
    >
      <.dynamic_tag
        tag_name={@level}
        class={classes([@base_class, @icon && "flex items-center gap-1.5", @heading_class])}
      >
        <Icon.icon :if={@icon} name={@icon} class={@icon_class} />
        {render_slot(@inner_block)}
      </.dynamic_tag>
      <p :if={@description != []} class="text-muted-caption">
        {render_slot(@description)}
      </p>
    </div>
    """
  end
end
