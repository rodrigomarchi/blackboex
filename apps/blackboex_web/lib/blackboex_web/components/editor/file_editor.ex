defmodule BlackboexWeb.Components.Editor.FileEditor do
  @moduledoc """
  Displays the content of a selected file with syntax highlighting.

  Supports live content override for streaming during code generation.
  """

  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]
  import BlackboexWeb.Components.Editor.CodeViewer, only: [code_viewer: 1]
  import BlackboexWeb.ApiLive.Edit.Helpers, only: [render_markdown: 1]

  attr :file, :map, default: nil
  attr :live_content, :string, default: nil
  attr :streaming, :boolean, default: false
  attr :read_only, :boolean, default: false
  attr :class, :string, default: nil

  def file_editor(assigns) do
    content = assigns.live_content || (assigns.file && assigns.file.content) || ""
    is_markdown = assigns.file && String.ends_with?(assigns.file.path, ".md")

    assigns =
      assign(assigns,
        display_content: content,
        is_markdown: is_markdown
      )

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
          <%= if @read_only do %>
            <span class="ml-2 flex items-center gap-1 text-[10px] text-muted-foreground">
              <span class="hero-lock-closed size-2.5"></span> generated
            </span>
          <% end %>
        </div>
        <div class="flex-1 min-h-0 relative" id="editor-scroll-region" phx-hook="EditorAutoScroll">
          <%= if @is_markdown do %>
            <div class="absolute inset-0 overflow-y-auto p-6">
              <div class="prose prose-sm dark:prose-invert max-w-none">
                {raw(render_markdown(@display_content))}
              </div>
            </div>
          <% else %>
            <.code_viewer code={@display_content} class="absolute inset-0" />
          <% end %>
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
