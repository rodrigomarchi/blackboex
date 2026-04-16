defmodule BlackboexWeb.Components.Editor.PlaygroundTree do
  @moduledoc """
  A sidebar component listing playgrounds for the playground editor.

  Displays project playgrounds in a flat list with selection state
  and hover actions, matching the visual pattern of `PageTree`.
  """

  use Phoenix.Component

  import BlackboexWeb.Components.Icon

  @doc """
  Renders a playground sidebar from a flat list of playgrounds.
  """
  attr :playgrounds, :list, required: true
  attr :current_playground_id, :string, default: nil

  @spec playground_tree(map()) :: Phoenix.LiveView.Rendered.t()
  def playground_tree(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-card border-r">
      <div class="flex items-center justify-between h-8 px-3 shrink-0 border-b">
        <span class="text-2xs font-semibold uppercase tracking-wider text-muted-foreground">
          Playgrounds
        </span>
        <button
          type="button"
          phx-click="new_playground"
          class="p-0.5 rounded text-muted-foreground hover:text-foreground hover:bg-accent"
          title="New playground"
        >
          <.icon name="hero-plus-micro" class="size-3.5" />
        </button>
      </div>
      <nav class="flex-1 overflow-y-auto py-1 text-xs" role="tree">
        <.playground_tree_node
          :for={pg <- @playgrounds}
          playground={pg}
          is_selected={pg.id == @current_playground_id}
        />
        <div :if={@playgrounds == []} class="px-3 py-4 text-center text-2xs text-muted-foreground">
          No playgrounds yet
        </div>
      </nav>
    </div>
    """
  end

  attr :playground, :map, required: true
  attr :is_selected, :boolean, default: false

  defp playground_tree_node(assigns) do
    ~H"""
    <div
      class={[
        "group flex items-center gap-1 py-0.5 pr-2 pl-2 cursor-pointer select-none rounded-sm mx-1",
        if(@is_selected,
          do: "bg-accent text-accent-foreground",
          else: "text-muted-foreground hover:bg-accent/50 hover:text-foreground"
        )
      ]}
      phx-click="select_playground"
      phx-value-slug={@playground.slug}
    >
      <.icon name="hero-code-bracket-micro" class="size-3.5 shrink-0 text-accent-emerald/80" />
      <span class="truncate">{@playground.name}</span>
    </div>
    """
  end
end
