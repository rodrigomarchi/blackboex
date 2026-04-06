defmodule BlackboexWeb.ApiLive.Edit.CodeLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell
  import BlackboexWeb.Components.Editor.CodeViewer

  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} ->
        api = socket.assigns.api
        files = Blackboex.Apis.list_files(api.id)

        code =
          files |> Enum.filter(&(&1.file_type == "source")) |> Enum.map_join("\n\n", & &1.content)

        test_code =
          files |> Enum.filter(&(&1.file_type == "test")) |> Enum.map_join("\n\n", & &1.content)

        socket =
          assign(socket,
            code: code,
            test_code: test_code
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
      <.code_viewer code={@code} label="Code" class="absolute inset-0" />
    </.editor_shell>
    """
  end

  # ── Command Palette Delegation ────────────────────────────────────────

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
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
