defmodule BlackboexWeb.Components.Sidebar.Menu do
  @moduledoc false
  use BlackboexWeb.Component

  import BlackboexWeb.Components.Skeleton
  import BlackboexWeb.Components.Tooltip

  @variant_config %{
    variants: %{
      variant: %{
        default: "hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
        outline:
          "bg-background shadow-[0_0_0_1px_hsl(var(--sidebar-border))] hover:bg-sidebar-accent hover:text-sidebar-accent-foreground hover:shadow-[0_0_0_1px_hsl(var(--sidebar-accent))]"
      },
      size: %{
        default: "h-8 text-sm",
        sm: "h-7 text-xs",
        lg: "h-12 text-sm group-data-[collapsible=icon]:!p-0"
      }
    },
    default_variants: %{
      variant: "default",
      size: "default"
    }
  }
  @shared_classes "peer/menu-button flex w-full items-center gap-2 overflow-hidden rounded-md p-2 text-left text-sm outline-none ring-sidebar-ring transition-[width,height,padding] hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 active:bg-sidebar-accent active:text-sidebar-accent-foreground disabled:pointer-events-none disabled:opacity-50 group-has-[[data-sidebar=menu-action]]/menu-item:pr-8 aria-disabled:pointer-events-none aria-disabled:opacity-50 data-[active=true]:bg-sidebar-accent data-[active=true]:font-medium data-[active=true]:text-sidebar-accent-foreground data-[state=open]:hover:bg-sidebar-accent data-[state=open]:hover:text-sidebar-accent-foreground group-data-[collapsible=icon]:!size-8 group-data-[collapsible=icon]:!p-2 [&>span:last-child]:truncate [&>svg]:size-4 [&>svg]:shrink-0"
  defp get_variant(input) do
    @shared_classes <> " " <> variant_class(@variant_config, input)
  end

  @doc """
  Render
  """
  attr(:class, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def sidebar_menu(assigns) do
    ~H"""
    <ul
      data-sidebar="menu"
      class={
        classes([
          "flex w-full min-w-0 flex-col gap-1",
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </ul>
    """
  end

  @doc """
  Render
  """
  attr(:class, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def sidebar_menu_item(assigns) do
    ~H"""
    <div
      data-sidebar="menu-item"
      class={
        classes([
          "group/menu-item relative",
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Render
  """
  attr :variant, :string, values: ~w(default outline), default: "default"
  attr :size, :string, values: ~w(default sm lg), default: "default"
  attr :is_active, :boolean, default: false
  attr(:class, :string, default: nil)
  attr :is_mobile, :boolean, default: false
  attr :state, :string, default: "expanded"
  attr :as_tag, :any, default: "button"
  attr(:rest, :global)
  slot(:inner_block, required: true)
  attr :tooltip, :string, required: false

  def sidebar_menu_button(assigns) do
    button = ~H"""
    <.dynamic
      tag={@as_tag}
      data-sidebar="menu-button"
      data-size={@size}
      data-active={@is_active}
      class={classes([get_variant(%{variant: @variant, size: @size}), @class])}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.dynamic>
    """

    assigns = assign(assigns, :button, button)

    if assigns[:tooltip] do
      ~H"""
      <.tooltip class="block">
        <.tooltip_trigger>
          {@button}
        </.tooltip_trigger>
        <.tooltip_content side="right" hidden={@state != "collapsed" || @is_mobile}>
          {@tooltip}
        </.tooltip_content>
      </.tooltip>
      """
    else
      button
    end
  end

  @doc """
  Render
  """
  attr(:class, :string, default: nil)
  attr :show_on_hover, :boolean, default: false
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def sidebar_menu_action(assigns) do
    ~H"""
    <button
      data-sidebar="menu-action"
      class={
        classes([
          "absolute right-1 top-1.5 flex aspect-square w-5 items-center justify-center rounded-md p-0 text-sidebar-foreground outline-none ring-sidebar-ring transition-transform hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 peer-hover/menu-button:text-sidebar-accent-foreground [&>svg]:size-4 [&>svg]:shrink-0",
          "after:absolute after:-inset-2 after:md:hidden",
          "peer-data-[size=sm]/menu-button:top-1",
          "peer-data-[size=default]/menu-button:top-1.5",
          "peer-data-[size=lg]/menu-button:top-2.5",
          "group-data-[collapsible=icon]:hidden",
          @show_on_hover &&
            "group-focus-within/menu-item:opacity-100 group-hover/menu-item:opacity-100 data-[state=open]:opacity-100 peer-data-[active=true]/menu-button:text-sidebar-accent-foreground md:opacity-0",
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Render
  """
  attr(:class, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def sidebar_menu_badge(assigns) do
    ~H"""
    <div
      data-sidebar="menu-badge"
      class={
        classes([
          "absolute right-1 flex h-5 min-w-5 items-center justify-center rounded-md px-1 text-xs font-medium tabular-nums text-sidebar-foreground select-none pointer-events-none",
          "peer-hover/menu-button:text-sidebar-accent-foreground peer-data-[active=true]/menu-button:text-sidebar-accent-foreground",
          "peer-data-[size=sm]/menu-button:top-1",
          "peer-data-[size=default]/menu-button:top-1.5",
          "peer-data-[size=lg]/menu-button:top-2.5",
          "group-data-[collapsible=icon]:hidden",
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Render
  """
  attr(:class, :string, default: nil)
  attr :show_icon, :boolean, default: false
  attr(:rest, :global)

  def sidebar_menu_skeleton(assigns) do
    width = :rand.uniform(40) + 50
    assigns = assign(assigns, :width, width)

    ~H"""
    <div
      data-sidebar="menu-skeleton"
      class={classes(["rounded-md h-8 flex gap-2 px-2 items-center", @class])}
      {@rest}
    >
      <.skeleton :if={@show_icon} class="size-4 rounded-md" data-sidebar="menu-skeleton-icon" />
      <.skeleton
        class="h-4 flex-1 max-w-[--skeleton-width]"
        data-sidebar="menu-skeleton-text"
        style={
          style([
            %{
              "--skeleton-width": @width
            }
          ])
        }
      />
    </div>
    """
  end

  @doc """
  Render
  """
  attr(:class, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def sidebar_menu_sub(assigns) do
    ~H"""
    <ul
      data-sidebar="menu-sub"
      class={
        classes([
          "mx-3.5 flex min-w-0 translate-x-px flex-col gap-1 border-l border-sidebar-border px-2.5 py-0.5",
          "group-data-[collapsible=icon]:hidden",
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </ul>
    """
  end

  @doc """
  Render
  """
  attr(:class, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def sidebar_menu_sub_item(assigns) do
    ~H"""
    <li
      class={
        classes([
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </li>
    """
  end

  @doc """
  Render
  """
  attr :size, :string, values: ~w(sm md), default: "md"
  attr :is_active, :boolean, default: false
  attr(:class, :string, default: nil)
  attr :as_tag, :any, default: "a"
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def sidebar_menu_sub_button(assigns) do
    ~H"""
    <.dynamic
      tag={@as_tag}
      data-sidebar="menu-sub-button"
      data-size={@size}
      data-active={@is_active}
      class={
        classes([
          "flex h-7 min-w-0 -translate-x-px items-center gap-2 overflow-hidden rounded-md px-2 text-sidebar-foreground outline-none ring-sidebar-ring hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 active:bg-sidebar-accent active:text-sidebar-accent-foreground disabled:pointer-events-none disabled:opacity-50 aria-disabled:pointer-events-none aria-disabled:opacity-50 [&>span:last-child]:truncate [&>svg]:size-4 [&>svg]:shrink-0 [&>svg]:text-sidebar-accent-foreground",
          "data-[active=true]:bg-sidebar-accent data-[active=true]:text-sidebar-accent-foreground",
          @size == "sm" && "text-xs",
          @size == "md" && "text-sm",
          "group-data-[collapsible=icon]:hidden",
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </.dynamic>
    """
  end
end
