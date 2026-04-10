defmodule BlackboexWeb.Components.Editor.ChatPanelHelpers do
  @moduledoc """
  Pure helper functions for ChatPanel — no socket, no HEEx.
  """

  alias Blackboex.CodeGen.DiffEngine

  @spec tool_icon(String.t()) :: String.t()
  def tool_icon("generate_code"), do: "hero-sparkles"
  def tool_icon("compile_code"), do: "hero-cog-6-tooth"
  def tool_icon("format_code"), do: "hero-paint-brush"
  def tool_icon("lint_code"), do: "hero-magnifying-glass"
  def tool_icon("generate_tests"), do: "hero-beaker"
  def tool_icon("run_tests"), do: "hero-play"
  def tool_icon("submit_code"), do: "hero-check-circle"
  def tool_icon("generate_docs"), do: "hero-document-text"
  def tool_icon("read_source"), do: "hero-document-text"
  def tool_icon("edit_source"), do: "hero-pencil-square"
  def tool_icon(_), do: "hero-wrench"

  @spec format_tool_display_name(String.t()) :: String.t()
  def format_tool_display_name("generate_code"), do: "Generate Code"
  def format_tool_display_name("compile_code"), do: "Compile"
  def format_tool_display_name("format_code"), do: "Format"
  def format_tool_display_name("lint_code"), do: "Lint"
  def format_tool_display_name("generate_tests"), do: "Generate Tests"
  def format_tool_display_name("run_tests"), do: "Run Tests"
  def format_tool_display_name("submit_code"), do: "Submit"
  def format_tool_display_name("generate_docs"), do: "Generate Docs"
  def format_tool_display_name("read_source"), do: "Read Source"
  def format_tool_display_name("edit_source"), do: "Edit Source"
  def format_tool_display_name(name), do: name

  @spec step_node_class(map() | nil) :: String.t()
  def step_node_class(nil), do: "border-info animate-pulse"
  def step_node_class(%{success: true}), do: "border-success"
  def step_node_class(%{success: false}), do: "border-destructive"
  def step_node_class(_), do: "border-muted-foreground/30"

  @spec compact_summary(String.t(), map() | nil) :: String.t() | nil
  def compact_summary(tool, nil) when tool in ~w(run_tests lint_code), do: nil

  def compact_summary("lint_code", %{success: true, content: content}) do
    if String.contains?(content, "No issues"), do: nil, else: parse_lint_count(content)
  end

  def compact_summary("run_tests", %{content: content}) do
    parse_test_count(content)
  end

  def compact_summary(_, _), do: nil

  @spec summary_color(String.t(), map() | nil) :: String.t()
  def summary_color("lint_code", %{success: true}), do: "text-warning-foreground"
  def summary_color("run_tests", %{success: true}), do: "text-success-foreground"
  def summary_color("run_tests", %{success: false}), do: "text-destructive"
  def summary_color(_, _), do: "text-muted-foreground"

  @spec compute_step_duration(map(), map() | nil) :: String.t()
  def compute_step_duration(call, nil) do
    format_duration_ms(call[:tool_duration_ms])
  end

  def compute_step_duration(call, result) do
    cond do
      result[:tool_duration_ms] ->
        format_duration_ms(result[:tool_duration_ms])

      call[:timestamp] && result[:timestamp] ->
        format_duration(call[:timestamp], result[:timestamp])

      true ->
        ""
    end
  end

  @spec format_duration_ms(integer() | nil) :: String.t()
  def format_duration_ms(nil), do: ""
  def format_duration_ms(ms) when ms < 1000, do: "#{ms}ms"
  def format_duration_ms(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  def format_duration_ms(ms), do: "#{div(ms, 60_000)}m #{rem(div(ms, 1000), 60)}s"

  @spec format_timestamp(DateTime.t() | NaiveDateTime.t() | nil | term()) :: String.t()
  def format_timestamp(nil), do: ""

  def format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  def format_timestamp(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  def format_timestamp(_), do: ""

  @spec format_tokens(integer() | nil) :: String.t()
  def format_tokens(nil), do: "0"
  def format_tokens(0), do: "0"
  def format_tokens(n) when n < 1000, do: to_string(n)
  def format_tokens(n) when n < 1_000_000, do: "#{Float.round(n / 1000, 1)}k"
  def format_tokens(n), do: "#{Float.round(n / 1_000_000, 1)}M"

  @spec format_cost(integer() | nil) :: String.t()
  def format_cost(nil), do: "$0"
  def format_cost(0), do: "$0"
  def format_cost(cents), do: "$#{Float.round(cents / 100, 2)}"

  @spec short_model(String.t() | nil) :: String.t()
  def short_model(nil), do: ""

  def short_model(model) do
    model
    |> String.replace(~r/^(claude-|gpt-)/, "")
    |> String.slice(0, 20)
  end

  @spec run_type_icon(String.t()) :: String.t()
  def run_type_icon("generation"), do: "hero-bolt"
  def run_type_icon("edit"), do: "hero-pencil-square"
  def run_type_icon("test_only"), do: "hero-beaker"
  def run_type_icon("doc_only"), do: "hero-document-text"
  def run_type_icon(_), do: "hero-bolt"

  @spec run_type_label(String.t()) :: String.t()
  def run_type_label("generation"), do: "Generation"
  def run_type_label("edit"), do: "Edit"
  def run_type_label("test_only"), do: "Test Only"
  def run_type_label("doc_only"), do: "Docs Only"
  def run_type_label(_), do: "Run"

  @spec diff_line_class(atom()) :: String.t()
  def diff_line_class(:ins), do: "bg-success/10 text-success-foreground"
  def diff_line_class(:del), do: "bg-destructive/10 text-destructive"
  def diff_line_class(:eq), do: ""

  @spec diff_prefix(atom()) :: String.t()
  def diff_prefix(:ins), do: "+"
  def diff_prefix(:del), do: "-"
  def diff_prefix(:eq), do: " "

  @spec format_diff_summary(list()) :: String.t()
  def format_diff_summary(diff), do: DiffEngine.format_diff_summary(diff)

  @spec test_summary(list() | nil | term()) :: String.t() | nil
  def test_summary(test_results) when is_list(test_results) and test_results != [] do
    passed =
      Enum.count(test_results, fn
        %{"status" => "passed"} -> true
        %{status: "passed"} -> true
        _ -> false
      end)

    total = length(test_results)
    "#{passed}/#{total}"
  end

  def test_summary(_), do: nil

  @spec quick_actions(String.t() | nil) :: list(String.t())
  def quick_actions("crud") do
    ["Add validation", "Add filter", "Add pagination", "Add error handling"]
  end

  def quick_actions("webhook") do
    ["Add validation", "Validate signature", "Add error handling"]
  end

  def quick_actions(_template_type) do
    ["Add validation", "Optimize performance", "Add error handling"]
  end

  @spec looks_like_code?(String.t() | nil) :: boolean()
  def looks_like_code?(nil), do: false
  def looks_like_code?(""), do: false

  def looks_like_code?(content) when is_binary(content) do
    String.contains?(content, "defmodule") or
      String.contains?(content, "defp ") or
      (String.contains?(content, "def ") and String.contains?(content, "do"))
  end

  @spec group_events(list(map())) :: list(tuple())
  def group_events(events) when is_list(events) do
    events
    |> Enum.chunk_while(
      nil,
      fn
        %{type: :tool_call} = call, nil ->
          {:cont, call}

        %{type: :tool_result, tool: tool} = result, %{type: :tool_call, tool: tool} = call ->
          {:cont, {:tool_group, call, result}, nil}

        event, %{type: :tool_call} = pending_call ->
          {:cont, {:tool_call, pending_call}, event}

        event, nil ->
          {:cont, {event_tag(event), event}, nil}

        event, prev when is_map(prev) ->
          {:cont, {event_tag(prev), prev}, event}
      end,
      fn
        nil -> {:cont, nil}
        %{type: :tool_call} = call -> {:cont, {:tool_call, call}, nil}
        event when is_map(event) -> {:cont, {event_tag(event), event}, nil}
        _ -> {:cont, nil}
      end
    )
    |> Enum.reject(&is_nil/1)
  end

  def group_events(_), do: []

  @spec has_active_tool_call?(list(tuple())) :: boolean()
  def has_active_tool_call?(grouped_events) do
    Enum.any?(grouped_events, fn
      {:tool_call, _call} -> true
      _ -> false
    end)
  end

  @spec event_tag(map()) :: atom()
  def event_tag(%{type: :message}), do: :message
  def event_tag(%{type: :tool_call}), do: :tool_call
  def event_tag(%{type: :tool_result}), do: :tool_result
  def event_tag(%{type: :status}), do: :status
  def event_tag(_), do: :status

  # Private helpers

  defp parse_lint_count(content) do
    case Regex.scan(~r/^\s*-\s/m, content) do
      [] -> nil
      matches -> "#{length(matches)} issues"
    end
  end

  defp parse_test_count(content) do
    cond do
      match = Regex.run(~r/(\d+) tests?,\s*(\d+) passed/, content) ->
        [_, total, passed] = match
        "#{passed}/#{total}"

      match = Regex.run(~r/(\d+) tests?.*?(\d+) failure/, content) ->
        [_, total, failed_count] = match
        passed = String.to_integer(total) - String.to_integer(failed_count)
        "#{passed}/#{total}"

      true ->
        nil
    end
  end

  defp format_duration(nil, _), do: ""
  defp format_duration(_, nil), do: ""

  defp format_duration(start_dt, end_dt) do
    diff_ms = DateTime.diff(end_dt, start_dt, :millisecond)
    format_duration_ms(max(diff_ms, 0))
  end
end
