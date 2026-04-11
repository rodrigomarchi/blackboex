defmodule BlackboexWeb.Components.Editor.CommandPalette do
  @moduledoc """
  Command palette modal for quick access to editor actions via fuzzy search.
  Supports keyboard navigation (arrows + Enter).
  """
  use BlackboexWeb, :html

  import BlackboexWeb.Components.UI.InlineInput

  attr :open, :boolean, default: false
  attr :query, :string, default: ""
  attr :api, :map, required: true
  attr :selected_index, :integer, default: 0

  @spec command_palette(map()) :: Phoenix.LiveView.Rendered.t()
  def command_palette(assigns) do
    assigns = assign(assigns, :filtered_commands, filter_commands(assigns.query, assigns.api))

    ~H"""
    <div
      :if={@open}
      data-command-palette
      class="fixed inset-0 z-50 flex items-start justify-center pt-[20vh]"
    >
      <%!-- Backdrop --%>
      <div class="fixed inset-0 bg-black/15" phx-click="toggle_command_palette" />

      <%!-- Palette --%>
      <div class="relative z-10 w-full max-w-md rounded-lg border bg-card text-card-foreground shadow-2xl overflow-hidden">
        <.form
          for={%{}}
          as={:command}
          phx-change="command_palette_search"
          phx-submit="command_palette_exec_first"
        >
          <div class="border-b px-3 py-2">
            <.inline_input
              id="command-palette-input"
              name="command_query"
              value={@query}
              phx-debounce="50"
              placeholder="Search commands..."
              class="w-full rounded-none border-0 px-0 py-0 bg-transparent focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground"
              autofocus
              autocomplete="off"
              phx-hook="CommandPaletteNav"
            />
          </div>
        </.form>

        <div class="max-h-80 overflow-y-auto py-1" id="command-palette-list">
          <.button
            :for={{cmd, idx} <- Enum.with_index(@filtered_commands)}
            variant="ghost"
            phx-click="command_palette_exec"
            phx-value-event={cmd.event}
            data-cmd-index={idx}
            class={[
              "h-auto rounded-none flex w-full items-center justify-between px-3 py-2 text-sm text-left",
              if(idx == @selected_index,
                do: "bg-accent",
                else: "hover:bg-accent"
              )
            ]}
          >
            <span>{cmd.label}</span>
            <kbd :if={cmd.shortcut} class="text-2xs font-mono text-muted-foreground">
              {cmd.shortcut}
            </kbd>
          </.button>
          <p
            :if={@filtered_commands == []}
            class="px-3 py-4 text-sm text-muted-foreground text-center"
          >
            No commands found
          </p>
        </div>
      </div>
    </div>
    """
  end

  @commands [
    %{label: "Save", shortcut: "⌘S", event: "save", group: :file},
    %{label: "Toggle Chat", shortcut: "⌘L", event: "toggle_chat", group: :panel},
    %{label: "Toggle Testing", shortcut: "⌘J", event: "toggle_bottom_panel", group: :panel},
    %{label: "Toggle Config", shortcut: "⌘I", event: "toggle_config", group: :panel},
    %{label: "Quick Test GET /", shortcut: nil, event: "quick_test_get", group: :test},
    %{
      label: "Quick Test POST / with example",
      shortcut: nil,
      event: "quick_test_post",
      group: :test
    },
    %{label: "Generate sample data", shortcut: nil, event: "generate_sample", group: :test},
    %{label: "Copy curl snippet", shortcut: nil, event: "copy_snippet_curl", group: :snippet},
    %{label: "Copy Python snippet", shortcut: nil, event: "copy_snippet_python", group: :snippet},
    %{
      label: "Copy JavaScript snippet",
      shortcut: nil,
      event: "copy_snippet_javascript",
      group: :snippet
    },
    %{label: "Copy Elixir snippet", shortcut: nil, event: "copy_snippet_elixir", group: :snippet},
    %{label: "Copy Ruby snippet", shortcut: nil, event: "copy_snippet_ruby", group: :snippet},
    %{label: "Copy Go snippet", shortcut: nil, event: "copy_snippet_go", group: :snippet}
  ]

  @publish_commands [
    %{label: "Publish API", shortcut: nil, event: "publish", group: :publish}
  ]

  @unpublish_commands [
    %{label: "Unpublish API", shortcut: nil, event: "unpublish", group: :publish}
  ]

  @doc """
  Returns filtered commands matching the given query for the given API.
  Public so that the parent LiveView can call it for Enter-to-execute.
  """
  @spec filter_commands(String.t(), map()) :: [map()]
  def filter_commands(query, api) do
    all_commands = @commands ++ publish_commands(api)

    if query == "" do
      all_commands
    else
      query_down = String.downcase(query)

      Enum.filter(all_commands, fn cmd ->
        String.contains?(String.downcase(cmd.label), query_down)
      end)
    end
  end

  defp publish_commands(%{status: "compiled"}), do: @publish_commands
  defp publish_commands(%{status: "published"}), do: @unpublish_commands
  defp publish_commands(_), do: []
end
