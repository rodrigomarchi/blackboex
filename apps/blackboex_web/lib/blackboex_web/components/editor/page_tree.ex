defmodule BlackboexWeb.Components.Editor.PageTree do
  @moduledoc """
  A collapsible page tree component for the page editor sidebar.

  Displays project pages in a nested hierarchy with expand/collapse,
  selection state, and hover actions for creating child pages.
  """

  use Phoenix.Component

  import BlackboexWeb.Components.Icon

  @doc """
  Renders a page tree sidebar from a nested tree structure.

  Each node is `%{page: %Page{}, children: [...]}`
  as returned by `Pages.list_page_tree/1`.
  """
  attr :tree, :list, required: true
  attr :current_page_id, :string, default: nil
  attr :expanded_ids, :list, default: []

  @spec page_tree(map()) :: Phoenix.LiveView.Rendered.t()
  def page_tree(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-card border-r">
      <div class="flex items-center justify-between h-8 px-3 shrink-0 border-b">
        <span class="text-2xs font-semibold uppercase tracking-wider text-muted-foreground">
          Pages
        </span>
        <button
          type="button"
          phx-click="new_page"
          class="p-0.5 rounded text-muted-foreground hover:text-foreground hover:bg-accent"
          title="New page"
        >
          <.icon name="hero-plus-micro" class="size-3.5" />
        </button>
      </div>
      <nav class="flex-1 overflow-y-auto py-1 text-xs" role="tree">
        <.page_tree_node
          :for={node <- @tree}
          node={node}
          current_page_id={@current_page_id}
          expanded_ids={@expanded_ids}
          depth={0}
        />
        <div :if={@tree == []} class="px-3 py-4 text-center text-2xs text-muted-foreground">
          No pages yet
        </div>
      </nav>
    </div>
    """
  end

  attr :node, :map, required: true
  attr :current_page_id, :string, default: nil
  attr :expanded_ids, :list, default: []
  attr :depth, :integer, default: 0

  defp page_tree_node(assigns) do
    assigns =
      assign(assigns,
        has_children: assigns.node.children != [],
        is_expanded: assigns.node.page.id in assigns.expanded_ids,
        is_selected: assigns.node.page.id == assigns.current_page_id
      )

    ~H"""
    <div role="treeitem">
      <div
        class={[
          "group flex items-center gap-1 py-0.5 pr-2 cursor-pointer select-none rounded-sm mx-1",
          if(@is_selected,
            do: "bg-accent text-accent-foreground",
            else: "text-muted-foreground hover:bg-accent/50 hover:text-foreground"
          )
        ]}
        style={"padding-left: #{@depth * 16 + 8}px"}
        phx-click="select_page"
        phx-value-slug={@node.page.slug}
      >
        <button
          :if={@has_children}
          type="button"
          phx-click="toggle_tree_node"
          phx-value-id={@node.page.id}
          class="shrink-0 p-0.5"
        >
          <.icon
            name={if @is_expanded, do: "hero-chevron-down-micro", else: "hero-chevron-right-micro"}
            class="size-3"
          />
        </button>
        <span :if={!@has_children} class="w-4 shrink-0" />

        <.icon name="hero-document-text-micro" class="size-3.5 shrink-0 text-accent-sky/80" />
        <span class="truncate">{@node.page.title}</span>

        <div class="ml-auto flex items-center gap-0.5 shrink-0 opacity-0 group-hover:opacity-100">
          <button
            type="button"
            class="p-0.5 rounded text-muted-foreground hover:text-foreground"
            phx-click="new_child_page"
            phx-value-parent-id={@node.page.id}
            title="New sub-page"
          >
            <.icon name="hero-plus-micro" class="size-2.5" />
          </button>
          <button
            type="button"
            class="p-0.5 rounded text-muted-foreground hover:text-destructive"
            phx-click="request_confirm"
            phx-value-action="delete"
            phx-value-id={@node.page.id}
            phx-value-slug={@node.page.slug}
            phx-value-title={@node.page.title}
            title="Delete page"
            aria-label="Delete page"
          >
            <.icon name="hero-trash-micro" class="size-2.5" />
          </button>
        </div>
      </div>

      <div :if={@has_children and @is_expanded} role="group">
        <.page_tree_node
          :for={child <- @node.children}
          node={child}
          current_page_id={@current_page_id}
          expanded_ids={@expanded_ids}
          depth={@depth + 1}
        />
      </div>
    </div>
    """
  end
end
