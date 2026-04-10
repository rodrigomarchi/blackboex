defmodule BlackboexWeb.ApiLive.Edit.ChatLiveHelpers do
  @moduledoc """
  Pure helper functions for the ChatLive view.
  Contains event display conversion, pipeline status mapping,
  streaming content helpers, and validation report restoration.
  """

  # ── Event display conversion ───────────────────────────────────────────

  @spec event_to_display(map()) :: map() | nil
  def event_to_display(%{event_type: "user_message"} = e) do
    %{type: :message, role: "user", content: e.content, timestamp: e.inserted_at, id: e.sequence}
  end

  def event_to_display(%{event_type: "assistant_message"} = e) do
    %{
      type: :message,
      role: "assistant",
      content: e.content,
      timestamp: e.inserted_at,
      id: e.sequence
    }
  end

  def event_to_display(%{event_type: "tool_call"} = e) do
    args = normalize_tool_input(e.tool_input)

    %{
      type: :tool_call,
      tool: e.tool_name,
      args: args,
      timestamp: e.inserted_at,
      id: e.sequence,
      tool_duration_ms: e.tool_duration_ms
    }
  end

  def event_to_display(%{event_type: "tool_result"} = e) do
    %{
      type: :tool_result,
      tool: e.tool_name,
      success: e.tool_success,
      content: e.content || "",
      timestamp: e.inserted_at,
      id: e.sequence,
      tool_duration_ms: e.tool_duration_ms
    }
  end

  def event_to_display(%{event_type: "status_change"} = e) do
    %{type: :status, content: e.content, timestamp: e.inserted_at, id: e.sequence}
  end

  def event_to_display(_), do: nil

  # ── Tool input normalization ───────────────────────────────────────────

  @spec normalize_tool_input(any()) :: map()
  def normalize_tool_input(nil), do: %{}

  def normalize_tool_input(args) when is_map(args),
    do: Map.new(args, fn {k, v} -> {to_string(k), v} end)

  def normalize_tool_input(_), do: %{}

  # ── Pipeline status mapping ────────────────────────────────────────────

  @spec pipeline_step_to_status(atom()) :: atom()
  def pipeline_step_to_status(:generating_code), do: :generating
  def pipeline_step_to_status(:generating_tests), do: :generating_tests
  def pipeline_step_to_status(:compiling), do: :compiling
  def pipeline_step_to_status(:formatting), do: :formatting
  def pipeline_step_to_status(:linting), do: :linting
  def pipeline_step_to_status(:fixing_compilation), do: :fixing
  def pipeline_step_to_status(:fixing_lint), do: :fixing
  def pipeline_step_to_status(:fixing_tests), do: :fixing
  def pipeline_step_to_status(:generating_docs), do: :generating_docs
  def pipeline_step_to_status(:submitting), do: :submitting
  def pipeline_step_to_status(_), do: :processing

  @spec agent_tool_to_status(String.t()) :: atom()
  def agent_tool_to_status("generate_code"), do: :generating
  def agent_tool_to_status("compile_code"), do: :compiling
  def agent_tool_to_status("format_code"), do: :formatting
  def agent_tool_to_status("lint_code"), do: :linting
  def agent_tool_to_status("generate_tests"), do: :generating_tests
  def agent_tool_to_status("run_tests"), do: :running_tests
  def agent_tool_to_status("generate_docs"), do: :generating_docs
  def agent_tool_to_status("submit_code"), do: :submitting
  def agent_tool_to_status(_), do: :processing

  # ── Streaming content helpers ──────────────────────────────────────────

  @spec strip_code_fences(any()) :: String.t()
  def strip_code_fences(tokens) when is_binary(tokens) do
    tokens
    |> String.replace(~r/^.*?```(?:elixir)?\s*\n/s, "")
    |> String.replace(~r/```\s*$/s, "")
    |> String.trim_leading("\n")
  end

  def strip_code_fences(_), do: ""

  @spec classify_file(String.t() | nil) :: atom()
  def classify_file(nil), do: :unknown

  def classify_file(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "/src") -> :source
      String.starts_with?(path, "/test") -> :test
      String.ends_with?(path, ".md") -> :doc
      true -> :unknown
    end
  end

  @spec streaming_target(atom(), String.t() | nil) :: atom()
  def streaming_target(status, path) do
    file_type = classify_file(path)
    streaming_target_for(status, file_type)
  end

  defp streaming_target_for(status, :source)
       when status in [:generating, :compiling, :formatting, :linting],
       do: :streaming_source

  defp streaming_target_for(status, :test) when status in [:generating_tests, :running_tests],
    do: :streaming_test

  defp streaming_target_for(:generating_docs, :doc), do: :streaming_doc
  defp streaming_target_for(_status, file_type), do: file_type

  # ── Validation report helpers ──────────────────────────────────────────

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

      total = length(test_results)
      "#{passed}/#{total}"
    else
      nil
    end
  end

  defp safe_to_atom(nil), do: :pass
  defp safe_to_atom(val) when is_atom(val), do: val
  defp safe_to_atom(val) when val in ["pass", "fail", "skipped"], do: String.to_existing_atom(val)
  defp safe_to_atom(_), do: :pass

  # ── Confirm dialog ─────────────────────────────────────────────────────

  @spec build_confirm(String.t() | nil, map()) :: map() | nil
  def build_confirm("clear_conversation", _params) do
    %{
      title: "Clear conversation?",
      description: "The chat history will be cleared. Your API code will not be affected.",
      variant: :warning,
      confirm_label: "Clear",
      event: "clear_conversation",
      meta: %{}
    }
  end

  def build_confirm(_, _), do: nil

  # ── File helpers ───────────────────────────────────────────────────────

  @spec filename_from_path(map() | nil) :: String.t()
  def filename_from_path(%{path: path}) when is_binary(path), do: Path.basename(path)
  def filename_from_path(_), do: "file.txt"
end
