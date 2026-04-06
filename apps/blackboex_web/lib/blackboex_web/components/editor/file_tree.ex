defmodule BlackboexWeb.Components.Editor.FileTree do
  @moduledoc """
  A collapsible file tree component for the API editor workspace.

  Displays the virtual filesystem of an API project as a tree with
  directories and files. Supports selection and visual indicators.
  """

  use Phoenix.Component

  @doc """
  Renders a file tree from a list of ApiFile structs.
  """
  attr :files, :list, required: true
  attr :selected_path, :string, default: nil
  attr :generating, :boolean, default: false

  def file_tree(assigns) do
    tree = build_tree(assigns.files)
    assigns = assign(assigns, :tree, tree)

    ~H"""
    <div class="flex flex-col h-full bg-card border-r">
      <div class="flex items-center h-8 px-3 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground border-b shrink-0">
        Explorer
      </div>
      <nav class="flex-1 overflow-y-auto py-1 text-xs" role="tree">
        <.tree_node
          :for={node <- @tree}
          node={node}
          selected_path={@selected_path}
          depth={0}
          generating={@generating}
        />
      </nav>
    </div>
    """
  end

  attr :node, :map, required: true
  attr :selected_path, :string, default: nil
  attr :depth, :integer, default: 0
  attr :generating, :boolean, default: false

  defp tree_node(%{node: %{type: :directory}} = assigns) do
    ~H"""
    <div role="treeitem">
      <div
        class="flex items-center gap-1 px-2 py-0.5 text-muted-foreground cursor-default select-none"
        style={"padding-left: #{@depth * 12 + 8}px"}
      >
        <span class="hero-folder-open size-3.5 shrink-0 text-amber-500/80"></span>
        <span class="truncate">{@node.name}</span>
      </div>
      <div role="group">
        <.tree_node
          :for={child <- @node.children}
          node={child}
          selected_path={@selected_path}
          depth={@depth + 1}
          generating={@generating}
        />
      </div>
    </div>
    """
  end

  defp tree_node(%{node: %{type: :file}} = assigns) do
    ~H"""
    <div
      role="treeitem"
      phx-click="select_file"
      phx-value-path={@node.path}
      class={[
        "flex items-center gap-1 px-2 py-0.5 cursor-pointer select-none hover:bg-accent/50",
        if(@selected_path == @node.path,
          do: "bg-accent text-accent-foreground",
          else: "text-foreground/80"
        )
      ]}
      style={"padding-left: #{@depth * 12 + 8}px"}
    >
      <%= if @generating and @node.file_type == "source" do %>
        <span class="inline-block w-3.5 h-3.5 shrink-0 rounded-full border-2 border-amber-400 border-t-transparent animate-spin">
        </span>
      <% else %>
        <span class={["size-3.5 shrink-0", file_icon_class(@node.name)]}></span>
      <% end %>
      <span class="truncate">{@node.name}</span>
    </div>
    """
  end

  defp build_tree(files) do
    files
    |> Enum.map(fn file ->
      path = if is_binary(file.path), do: file.path, else: to_string(file.path)
      parts = path |> String.trim_leading("/") |> String.split("/")
      {parts, path, file.file_type}
    end)
    |> build_tree_nodes()
    |> Enum.sort_by(fn node -> {if(node.type == :directory, do: 0, else: 1), node.name} end)
  end

  defp build_tree_nodes(entries) do
    {files, dirs} =
      Enum.split_with(entries, fn {parts, _path, _type} -> length(parts) == 1 end)

    file_nodes =
      Enum.map(files, fn {[name], path, file_type} ->
        %{type: :file, name: name, path: path, file_type: file_type, children: []}
      end)

    dir_groups =
      dirs
      |> Enum.group_by(fn {[first | _rest], _path, _type} -> first end)
      |> Enum.map(fn {dir_name, children} ->
        sub_entries =
          Enum.map(children, fn {[_first | rest], path, type} -> {rest, path, type} end)

        %{
          type: :directory,
          name: dir_name,
          path: nil,
          file_type: nil,
          children:
            build_tree_nodes(sub_entries)
            |> Enum.sort_by(fn n -> {if(n.type == :directory, do: 0, else: 1), n.name} end)
        }
      end)

    dir_groups ++ file_nodes
  end

  defp file_icon_class(name) do
    cond do
      String.ends_with?(name, "_test.ex") -> "hero-beaker text-green-500/80"
      String.ends_with?(name, ".ex") -> "hero-code-bracket text-purple-500/80"
      true -> "hero-document text-muted-foreground"
    end
  end
end
