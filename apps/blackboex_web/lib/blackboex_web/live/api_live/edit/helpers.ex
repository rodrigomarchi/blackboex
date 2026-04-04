defmodule BlackboexWeb.ApiLive.Edit.Helpers do
  @moduledoc false

  use Phoenix.Component

  # ── Markdown ─────────────────────────────────────────────────────────

  @spec render_markdown(String.t() | nil) :: String.t()
  def render_markdown(nil), do: ""

  def render_markdown(markdown) do
    case MDEx.to_html(markdown,
           extension: [
             table: true,
             strikethrough: true,
             autolink: true,
             tasklist: true,
             footnotes: true
           ],
           render: [unsafe: false],
           syntax_highlight: [
             formatter: {:html_inline, theme: "github_dark"}
           ]
         ) do
      {:ok, html} -> html
      _ -> markdown
    end
  end

  # ── Time Formatting ──────────────────────────────────────────────────

  @spec time_ago(NaiveDateTime.t() | nil | term()) :: String.t()
  def time_ago(nil), do: "never"

  def time_ago(%NaiveDateTime{} = dt) do
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86_400 -> "#{div(diff, 3600)} hours ago"
      true -> "#{div(diff, 86_400)} days ago"
    end
  end

  def time_ago(_), do: "unknown"

  # ── Code Stats ───────────────────────────────────────────────────────

  @spec count_lines(String.t() | nil) :: non_neg_integer()
  def count_lines(nil), do: 0
  def count_lines(""), do: 0
  def count_lines(code), do: code |> String.split("\n") |> length()

  # ── JSON ─────────────────────────────────────────────────────────────

  @spec format_json(map() | nil | term()) :: String.t()
  def format_json(nil), do: ""
  def format_json(map) when is_map(map), do: Jason.encode!(map, pretty: true)
  def format_json(other), do: inspect(other)

  # ── Status Colors ────────────────────────────────────────────────────

  @spec history_status_color(integer()) :: String.t()
  def history_status_color(status) when status >= 200 and status < 300,
    do: "bg-success/10 text-success-foreground"

  def history_status_color(status) when status >= 400 and status < 500,
    do: "bg-warning/10 text-warning-foreground"

  def history_status_color(status) when status >= 500,
    do: "bg-destructive/10 text-destructive"

  def history_status_color(_), do: "bg-muted text-muted-foreground"

  @spec test_summary_class(String.t()) :: String.t()
  def test_summary_class(summary) do
    if String.contains?(summary, "/") do
      [passed, total] = String.split(summary, "/")

      if passed == total,
        do: "bg-success/10 text-success-foreground",
        else: "bg-destructive/10 text-destructive"
    else
      "bg-muted text-muted-foreground"
    end
  end

  # ── Validation Report ────────────────────────────────────────────────

  @spec restore_validation_report(map() | nil) :: map() | nil
  def restore_validation_report(nil), do: nil

  def restore_validation_report(report) when is_map(report) do
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

  @spec derive_test_summary(map() | nil) :: String.t() | nil
  def derive_test_summary(nil), do: nil

  def derive_test_summary(report) when is_map(report) do
    test_results = report["test_results"] || []

    if test_results != [] do
      passed =
        Enum.count(test_results, fn item -> (item[:status] || item["status"]) == "passed" end)

      "#{passed}/#{length(test_results)}"
    else
      nil
    end
  end

  # ── Editor ───────────────────────────────────────────────────────────

  @spec push_editor_value(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def push_editor_value(socket, code) do
    editor_path = "api_#{socket.assigns.api.id}.ex"
    LiveMonacoEditor.set_value(socket, code, to: editor_path)
  end

  @spec edit_tab_path(Phoenix.LiveView.Socket.t(), String.t()) :: String.t()
  def edit_tab_path(socket, tab) do
    "/apis/#{socket.assigns.api.id}/edit/#{tab}"
  end

  # ── Organization Resolution ──────────────────────────────────────────

  @spec resolve_organization(Phoenix.LiveView.Socket.t(), map()) :: map() | nil
  def resolve_organization(socket, params) do
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

  defp safe_to_atom(nil), do: :pass
  defp safe_to_atom(val) when is_atom(val), do: val
  defp safe_to_atom(val) when val in ["pass", "fail", "skipped"], do: String.to_existing_atom(val)
  defp safe_to_atom(_), do: :pass
end
