defmodule BlackboexWeb.Components.Sidebar.Group do
  @moduledoc false
  use BlackboexWeb.Component

  @doc """
  Render
  """
  attr(:class, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def sidebar_group(assigns) do
    ~H"""
    <div
      data-sidebar="group"
      class={
        classes([
          "relative flex w-full min-w-0 flex-col p-2",
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
  TODO: class merge not work well here
  """
  attr(:class, :string, default: nil)
  attr :as_tag, :any, default: "div"
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def sidebar_group_label(assigns) do
    ~H"""
    <.dynamic
      data-sidebar="group-label"
      tag={@as_tag}
      class={
        Enum.join(
          [
            "duration-200 flex h-8 shrink-0 items-center rounded-md px-2 font-medium text-sidebar-foreground/70 outline-none ring-sidebar-ring transition-[margin,opa] ease-linear focus-visible:ring-2 [&>svg]:size-4 [&>svg]:shrink-0 text-xs",
            "group-data-[collapsible=icon]:-mt-8 group-data-[collapsible=icon]:opacity-0",
            @class
          ],
          " "
        )
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </.dynamic>
    """
  end

  @doc """
  Render
  """
  attr(:class, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def sidebar_group_action(assigns) do
    ~H"""
    <button
      data-sidebar="group-action"
      class={
        classes([
          "absolute right-3 top-3.5 flex aspect-square w-5 items-center justify-center rounded-md p-0 text-sidebar-foreground outline-none ring-sidebar-ring transition-transform hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 [&>svg]:size-4 [&>svg]:shrink-0",
          "after:absolute after:-inset-2 after:md:hidden",
          "group-data-[collapsible=icon]:hidden",
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

  def sidebar_group_content(assigns) do
    ~H"""
    <div
      data-sidebar="group-content"
      class={
        classes([
          "w-full text-sm",
          @class
        ])
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end
end
