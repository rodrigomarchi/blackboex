defmodule BlackboexWeb.ApiLive.Edit.VersionsLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell

  alias Blackboex.Apis
  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} ->
        api = socket.assigns.api

        {:ok,
         assign(socket,
           code: api.source_code || "",
           test_code: api.test_code || ""
         )}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="versions">
      <div class="p-4 overflow-y-auto h-full space-y-2">
        <%= if @versions == [] do %>
          <p class="text-sm text-muted-foreground">
            No versions yet. Save to create the first version.
          </p>
        <% else %>
          <%= for version <- @versions do %>
            <div class={[
              "rounded border p-3 text-xs space-y-1",
              if(@selected_version && @selected_version.id == version.id,
                do: "border-primary bg-primary/5",
                else: ""
              )
            ]}>
              <div class="flex items-center justify-between">
                <span class="font-semibold">v{version.version_number}</span>
                <span class="text-muted-foreground">
                  {Calendar.strftime(version.inserted_at, "%H:%M")}
                </span>
              </div>
              <div class="text-muted-foreground">
                {version.source}
                <%= if version.diff_summary do %>
                  — {version.diff_summary}
                <% end %>
              </div>
              <div class="flex gap-2">
                <button
                  phx-click="view_version"
                  phx-value-number={version.version_number}
                  class="text-primary hover:underline"
                >
                  View
                </button>
                <%= if version.version_number != hd(@versions).version_number do %>
                  <button
                    phx-click="rollback"
                    phx-value-number={version.version_number}
                    class="text-orange-600 hover:underline"
                    data-confirm={"Rollback to v#{version.version_number}? This creates a new version."}
                  >
                    Restore
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </.editor_shell>
    """
  end

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
  end

  def handle_event("view_version", %{"number" => number_str}, socket) do
    number = String.to_integer(number_str)
    version = Apis.get_version(socket.assigns.api.id, number)

    if version do
      {:noreply,
       socket
       |> assign(code: version.code, selected_version: version)
       |> push_editor_value(version.code)}
    else
      {:noreply, put_flash(socket, :error, "Version not found")}
    end
  end

  def handle_event("clear_version_view", _params, socket) do
    api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)
    code = api.source_code || ""

    {:noreply,
     socket
     |> assign(code: code, selected_version: nil, api: api)
     |> push_editor_value(code)}
  end

  def handle_event("rollback", %{"number" => number_str}, socket) do
    number = String.to_integer(number_str)
    api = socket.assigns.api
    scope = socket.assigns.current_scope

    case Apis.rollback_to_version(api, number, scope.user.id) do
      {:ok, new_version} ->
        api = Apis.get_api(socket.assigns.org.id, api.id)
        code = new_version.code
        test_code = new_version.test_code || socket.assigns.test_code

        {:noreply,
         socket
         |> assign(
           api: api,
           code: code,
           test_code: test_code,
           versions: Apis.list_versions(api.id),
           selected_version: nil,
           validation_report: restore_validation_report(api.validation_report),
           test_summary: derive_test_summary(api.validation_report)
         )
         |> push_editor_value(code)
         |> put_flash(:info, "Rolled back to v#{number}")}

      {:error, :version_not_found} ->
        {:noreply, put_flash(socket, :error, "Version not found")}
    end
  end

  # ── Private ───────────────────────────────────────────────────────────

  @spec push_editor_value(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp push_editor_value(socket, code) do
    editor_path = "api_#{socket.assigns.api.id}.ex"
    LiveMonacoEditor.set_value(socket, code, to: editor_path)
  end

  @spec restore_validation_report(map() | nil) :: map() | nil
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

  @spec safe_to_atom(term()) :: atom()
  defp safe_to_atom(nil), do: :pass
  defp safe_to_atom(val) when is_atom(val), do: val
  defp safe_to_atom(val) when val in ["pass", "fail", "skipped"], do: String.to_existing_atom(val)
  defp safe_to_atom(_), do: :pass

  @spec derive_test_summary(map() | nil) :: String.t() | nil
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

  @spec shared_shell_assigns(map()) :: map()
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
