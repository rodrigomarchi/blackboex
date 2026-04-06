defmodule BlackboexWeb.Components.Editor.FileEditor do
  @moduledoc """
  Displays the content of a selected file with syntax highlighting.

  Supports live content override for streaming during code generation,
  showing the code being written in real-time.
  """

  use Phoenix.Component

  import BlackboexWeb.Components.Editor.CodeViewer, only: [code_viewer: 1]

  attr :file, :map, default: nil
  attr :live_content, :string, default: nil
  attr :streaming, :boolean, default: false
  attr :class, :string, default: nil

  def file_editor(assigns) do
    content = assigns.live_content || (assigns.file && assigns.file.content) || ""
    assigns = assign(assigns, :display_content, content)

    ~H"""
    <div class={["flex flex-col h-full bg-[#1e1e2e]", @class]}>
      <%= if @file do %>
        <div class="flex items-center h-8 px-3 border-b border-white/10 shrink-0">
          <span class="text-[10px] text-white/60 font-mono truncate">{@file.path}</span>
          <%= if @streaming do %>
            <span class="ml-2 flex items-center gap-1 text-[10px] text-amber-400/80">
              <span class="inline-block w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse"></span>
              generating
            </span>
          <% end %>
        </div>
        <div class="flex-1 min-h-0 relative">
          <.code_viewer code={@display_content} class="absolute inset-0" />
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
