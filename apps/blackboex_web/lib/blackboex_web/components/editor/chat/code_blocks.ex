defmodule BlackboexWeb.Components.Editor.Chat.CodeBlocks do
  @moduledoc """
  Function components for rendering code blocks in the chat panel.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Editor.ChatPanelHelpers, only: [looks_like_code?: 1]
  import BlackboexWeb.Components.Editor.CodeLabel
  import BlackboexWeb.Components.Shared.CodeEditorField

  @makeup_mod Makeup
  @elixir_lexer Makeup.Lexers.ElixirLexer

  @doc "Renders a code block with line numbers and syntax highlighting."
  attr :code, :string, required: true
  attr :label, :string, default: "Streaming"
  attr :streaming, :boolean, default: false

  def render_code_block(assigns) do
    lines = String.split(assigns.code, "\n")
    line_count = length(lines)

    assigns =
      assigns
      |> assign(:line_count, line_count)
      |> assign(:lines, Enum.with_index(lines, 1))

    ~H"""
    <div class="rounded-md border bg-editor-bg overflow-hidden">
      <div class="flex items-center justify-between px-2.5 py-1 border-b border-white/10 bg-white/5">
        <.code_label variant="dark">{@label}</.code_label>
        <%= if @streaming do %>
          <span class="inline-block w-1.5 h-3 bg-info animate-pulse rounded-sm" />
        <% else %>
          <span class="text-2xs text-white/40">{@line_count} lines</span>
        <% end %>
      </div>
      <div
        class="max-h-[300px] overflow-y-auto overflow-x-auto font-mono"
        style="font-size: var(--content-font-xs); line-height: 1.6;"
      >
        <%= for {line, num} <- @lines do %>
          <div class="flex hover:bg-white/5">
            <span class="select-none text-white/20 text-right w-8 pr-2 pl-2 shrink-0 border-r border-white/5">
              {num}
            </span>
            <span class="pl-3 pr-2 whitespace-pre highlight">{highlight_line(line)}</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc "Renders a streaming code block with animated cursor."
  attr :code, :string, required: true

  def render_streaming_code(assigns) do
    assigns = assign(assigns, :label, "Streaming")

    ~H"""
    <.render_code_block code={@code} label={@label} streaming />
    """
  end

  @doc "Renders tool output, using a code block for code-like content or a CodeEditor for other output."
  attr :tool, :string, required: true
  attr :success, :boolean, required: true
  attr :content, :string, required: true

  def render_tool_output(assigns) do
    assigns = assign(assigns, :is_code, looks_like_code?(assigns.content))

    ~H"""
    <%= if @content != "" do %>
      <%= if @is_code do %>
        <.render_code_block code={@content} label="Output" />
      <% else %>
        <div class={[
          "rounded-md border px-2.5 py-2 text-xs",
          if(!@success,
            do: "border-destructive bg-destructive/10",
            else: "bg-muted/30"
          )
        ]}>
          <div class="flex items-center gap-1 mb-1">
            <.code_label>Output</.code_label>
            <%= if !@success do %>
              <span class="text-2xs rounded bg-destructive/10 text-destructive px-1 py-0.5 font-medium">
                ERROR
              </span>
            <% end %>
          </div>
          <.code_editor_field
            id={"chat-code-block-#{System.unique_integer([:positive])}"}
            value={@content}
            max_height="max-h-[400px]"
            class={if(!@success, do: "[&_.cm-editor_.cm-content]:text-destructive", else: nil)}
          />
        </div>
      <% end %>
    <% end %>
    """
  end

  @spec highlight_line(String.t()) :: Phoenix.HTML.safe()
  defp highlight_line(line) do
    @makeup_mod.highlight_inner_html(line, lexer: @elixir_lexer)
    |> Phoenix.HTML.raw()
  rescue
    _ -> line
  end
end
