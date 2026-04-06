defmodule BlackboexWeb.Components.Editor.FileEditor do
  @moduledoc """
  Displays the content of a selected file with syntax highlighting.

  Uses the same Makeup-based code viewer as the standalone CodeLive tab,
  but scoped to a single file within the workspace layout.
  """

  use Phoenix.Component

  import BlackboexWeb.Components.Editor.CodeViewer, only: [code_viewer: 1]

  attr :file, :map, default: nil
  attr :class, :string, default: nil

  def file_editor(assigns) do
    ~H"""
    <div class={["flex flex-col h-full bg-[#1e1e2e]", @class]}>
      <%= if @file do %>
        <div class="flex items-center h-8 px-3 border-b border-white/10 shrink-0">
          <span class="text-[10px] text-white/60 font-mono truncate">{@file.path}</span>
        </div>
        <div class="flex-1 min-h-0 relative">
          <.code_viewer code={@file.content || ""} class="absolute inset-0" />
        </div>
      <% else %>
        <div class="flex items-center justify-center h-full text-sm text-white/30">
          Select a file to view
        </div>
      <% end %>
    </div>
    """
  end
end
