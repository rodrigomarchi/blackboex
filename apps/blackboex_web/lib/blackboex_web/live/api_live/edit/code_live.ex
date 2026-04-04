defmodule BlackboexWeb.ApiLive.Edit.CodeLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell

  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} ->
        api = socket.assigns.api

        socket =
          assign(socket,
            code: api.source_code || "",
            test_code: api.test_code || ""
          )

        {:ok, socket}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="code">
      <div
        id="monaco-container"
        style="position: absolute; top: 0; left: 0; right: 0; bottom: 0;"
      >
        <LiveMonacoEditor.code_editor
          path={"api_#{@api.id}.ex"}
          value={@code}
          change="editor_changed"
          style="position: absolute; top: 0; left: 0; right: 0; bottom: 0;"
          opts={
            Map.merge(LiveMonacoEditor.default_opts(), %{
              "language" => "elixir",
              "fontSize" => 14,
              "minimap" => %{"enabled" => false},
              "wordWrap" => "on",
              "scrollBeyondLastLine" => false,
              "automaticLayout" => true,
              "scrollbar" => %{"alwaysConsumeMouseWheel" => true},
              "readOnly" =>
                @selected_version != nil or
                  @generation_status in ["pending", "generating", "validating"]
            })
          }
        />
      </div>
    </.editor_shell>
    """
  end

  # ── Command Palette Delegation ────────────────────────────────────────

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
  end

  # ── Tab-Specific Events ───────────────────────────────────────────────

  def handle_event("editor_changed", %{"value" => value}, socket) do
    {:noreply, assign(socket, code: value)}
  end

  # ── Private Helpers ───────────────────────────────────────────────────

  defp shared_shell_assigns(assigns) do
    Map.take(assigns, [
      :api,
      :versions,
      :selected_version,
      :generation_status,
      :validation_report,
      :test_summary,
      :command_palette_open,
      :command_palette_query,
      :command_palette_selected
    ])
  end
end
