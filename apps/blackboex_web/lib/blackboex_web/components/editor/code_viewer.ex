defmodule BlackboexWeb.Components.Editor.CodeViewer do
  @moduledoc """
  Read-only code viewer with Makeup-based Elixir syntax highlighting.

  Renders server-side highlighted Elixir code with line numbers and Monokai theme.
  Used in the code and tests editor tabs.
  """

  use Phoenix.Component

  @makeup_mod Makeup
  @elixir_lexer Makeup.Lexers.ElixirLexer

  @doc """
  Renders a full-height, scrollable code viewer with line numbers and syntax highlighting.

  ## Attributes

    * `code` - The source code to display (required)
    * `label` - Optional header label (e.g., "Code", "Tests")
    * `class` - Additional CSS classes for the outer container
  """
  attr :code, :string, required: true
  attr :label, :string, default: nil
  attr :class, :string, default: nil

  @spec code_viewer(map()) :: Phoenix.LiveView.Rendered.t()
  def code_viewer(assigns) do
    lines = String.split(assigns.code, "\n")

    assigns =
      assigns
      |> assign(:line_count, length(lines))
      |> assign(:lines, Enum.with_index(lines, 1))
      |> assign(:gutter_width, gutter_width(length(lines)))

    ~H"""
    <div class={["h-full flex flex-col bg-[#1e1e2e] overflow-hidden", @class]}>
      <div
        :if={@label}
        class="flex items-center justify-between px-2.5 py-1 border-b border-white/10 bg-white/5 shrink-0"
      >
        <span class="text-[10px] font-medium text-white/50 uppercase tracking-wider">
          {@label}
        </span>
        <span class="text-[10px] text-white/40">{@line_count} lines</span>
      </div>
      <div class="flex-1 overflow-y-auto overflow-x-auto text-sm font-mono leading-relaxed">
        <%= for {line, num} <- @lines do %>
          <div class="flex hover:bg-white/5">
            <span class={[
              "select-none text-white/20 text-right pr-3 pl-2 shrink-0 border-r border-white/5",
              @gutter_width
            ]}>
              {num}
            </span>
            <span class="pl-3 pr-2 whitespace-pre highlight">{highlight_line(line)}</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @spec highlight_line(String.t()) :: Phoenix.HTML.safe()
  defp highlight_line(line) do
    @makeup_mod.highlight_inner_html(line, lexer: @elixir_lexer)
    |> Phoenix.HTML.raw()
  rescue
    _ -> line
  end

  @spec gutter_width(non_neg_integer()) :: String.t()
  defp gutter_width(line_count) when line_count < 100, do: "w-8"
  defp gutter_width(line_count) when line_count < 1000, do: "w-10"
  defp gutter_width(_line_count), do: "w-12"
end
