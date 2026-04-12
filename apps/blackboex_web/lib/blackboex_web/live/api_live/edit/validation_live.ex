defmodule BlackboexWeb.ApiLive.Edit.ValidationLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell
  import BlackboexWeb.Components.Editor.ValidationDashboard

  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette toggle_chat close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} ->
        {:ok, assign(socket, pipeline_status: nil)}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="validation">
      <.editor_tab_panel padding="sm" spacing="none">
        <.validation_dashboard
          report={@validation_report}
          loading={@pipeline_status != nil && @pipeline_status != :done}
        />
      </.editor_tab_panel>
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
