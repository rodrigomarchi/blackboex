defmodule BlackboexWeb.ApiLive.Edit.Shared do
  @moduledoc """
  Shared mount logic and command palette handling for all Edit LiveViews.
  Each tab LiveView calls `load_api/2` in its mount and delegates
  command palette events to this module.
  """

  import Phoenix.Component
  import Phoenix.LiveView
  use Phoenix.VerifiedRoutes, endpoint: BlackboexWeb.Endpoint, router: BlackboexWeb.Router

  alias Blackboex.Apis

  @spec load_api(Phoenix.LiveView.Socket.t(), map()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:error, Phoenix.LiveView.Socket.t()}
  def load_api(socket, params) do
    org = resolve_organization(socket, params)
    scope = socket.assigns.current_scope

    api =
      cond do
        params["api_slug"] && scope.project ->
          Apis.get_api_by_slug(scope.project.id, params["api_slug"])

        params["id"] && org ->
          Apis.get_api(org.id, params["id"])

        true ->
          nil
      end

    case api do
      nil ->
        {:error,
         socket
         |> put_flash(:error, "API not found")
         |> push_navigate(to: ~p"/apis")}

      api ->
        {:ok,
         assign(socket,
           api: api,
           org: org,
           page_title: "Edit: #{api.name}",
           versions: Apis.list_versions(api.id),
           selected_version: nil,
           generation_status: api.generation_status,
           validation_report: restore_validation_report(api.validation_report),
           test_summary: derive_test_summary(api.validation_report),
           command_palette_open: false,
           command_palette_query: "",
           command_palette_selected: 0
         )}
    end
  end

  # ── Command Palette Events ──────────────────────────────────────────

  import BlackboexWeb.Components.Editor.CommandPalette, only: [filter_commands: 2]

  @spec handle_command_palette(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_command_palette("toggle_command_palette", _params, socket) do
    {:noreply,
     assign(socket,
       command_palette_open: !socket.assigns.command_palette_open,
       command_palette_query: "",
       command_palette_selected: 0
     )}
  end

  def handle_command_palette("close_panels", _params, socket) do
    if socket.assigns.command_palette_open do
      {:noreply, assign(socket, command_palette_open: false, command_palette_query: "")}
    else
      {:noreply, socket}
    end
  end

  def handle_command_palette("command_palette_search", %{"command_query" => query}, socket) do
    {:noreply, assign(socket, command_palette_query: query, command_palette_selected: 0)}
  end

  def handle_command_palette("command_palette_navigate", %{"direction" => "up"}, socket) do
    idx = max(socket.assigns.command_palette_selected - 1, 0)
    {:noreply, assign(socket, command_palette_selected: idx)}
  end

  def handle_command_palette("command_palette_navigate", %{"direction" => "down"}, socket) do
    commands = filter_commands(socket.assigns.command_palette_query, socket.assigns.api)
    idx = min(socket.assigns.command_palette_selected + 1, length(commands) - 1)
    {:noreply, assign(socket, command_palette_selected: idx)}
  end

  def handle_command_palette("command_palette_exec", %{"event" => event_name}, socket) do
    socket = assign(socket, command_palette_open: false, command_palette_query: "")
    {:noreply, push_navigate(socket, to: command_to_path(socket, event_name))}
  end

  def handle_command_palette("command_palette_exec_first", _params, socket) do
    commands = filter_commands(socket.assigns.command_palette_query, socket.assigns.api)

    case Enum.at(commands, socket.assigns.command_palette_selected) do
      nil ->
        {:noreply, socket}

      cmd ->
        socket =
          assign(socket,
            command_palette_open: false,
            command_palette_query: "",
            command_palette_selected: 0
          )

        {:noreply, push_navigate(socket, to: command_to_path(socket, cmd.event))}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  @spec edit_tab_path(Phoenix.LiveView.Socket.t(), String.t()) :: String.t()
  def edit_tab_path(socket, tab) do
    "/apis/#{socket.assigns.api.id}/edit/#{tab}"
  end

  defp command_to_path(socket, "toggle_chat"), do: edit_tab_path(socket, "chat")
  defp command_to_path(socket, "toggle_config"), do: edit_tab_path(socket, "publish")
  defp command_to_path(socket, "toggle_bottom_panel"), do: edit_tab_path(socket, "run")
  defp command_to_path(socket, "switch_tab_" <> tab), do: edit_tab_path(socket, tab)
  defp command_to_path(socket, _), do: edit_tab_path(socket, "chat")

  defp resolve_organization(socket, params) do
    scope = socket.assigns.current_scope

    case params["org"] do
      nil ->
        scope.organization

      org_id ->
        org = Blackboex.Organizations.get_organization(org_id)

        if org && Blackboex.Organizations.get_user_membership(org, scope.user) do
          org
        else
          nil
        end
    end
  end

  defp restore_validation_report(nil), do: nil

  defp restore_validation_report(report) when is_map(report) do
    %{
      compilation: safe_to_atom(report["compilation"]),
      compilation_errors: report["compilation_errors"] || [],
      format: safe_to_atom(report["format"]),
      format_issues: report["format_issues"] || [],
      credo: safe_to_atom(report["credo"]),
      credo_issues: report["credo_issues"] || [],
      tests: safe_to_atom(report["tests"]),
      test_results: report["test_results"] || [],
      overall: safe_to_atom(report["overall"])
    }
  end

  defp safe_to_atom(nil), do: :pass
  defp safe_to_atom(val) when is_atom(val), do: val
  defp safe_to_atom(val) when val in ["pass", "fail", "skipped"], do: String.to_existing_atom(val)
  defp safe_to_atom(_), do: :pass

  defp derive_test_summary(nil), do: nil

  defp derive_test_summary(report) when is_map(report) do
    test_results = report["test_results"] || []

    if test_results != [] do
      passed =
        Enum.count(test_results, fn item -> (item[:status] || item["status"]) == "passed" end)

      "#{passed}/#{length(test_results)}"
    else
      nil
    end
  end
end
