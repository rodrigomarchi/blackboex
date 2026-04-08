defmodule Blackboex.Agent.Session.EventTranslator do
  @moduledoc """
  Translates pipeline events to DB persistence and PubSub broadcasts.
  """

  require Logger

  alias Blackboex.Agent.Session
  alias Blackboex.Agent.Session.StreamManager
  alias Blackboex.Apis
  alias Blackboex.Conversations

  @spec translate_pipeline_event(term(), String.t(), String.t(), String.t(), String.t()) :: :ok
  def translate_pipeline_event(
        {:step_started, %{step: step}},
        run_id,
        conversation_id,
        _api_id,
        _org_id
      ) do
    StreamManager.flush_remaining_stream(run_id)
    tool_name = step_to_tool_name(step)

    persist_event(%{
      run_id: run_id,
      conversation_id: conversation_id,
      event_type: "tool_call",
      tool_name: tool_name,
      tool_input: %{}
    })

    Session.broadcast(run_id, {:agent_action, %{tool: tool_name, args: %{}, run_id: run_id}})
  end

  def translate_pipeline_event(
        {:step_completed, %{step: step} = payload},
        run_id,
        conversation_id,
        api_id,
        org_id
      ) do
    tool_name = step_to_tool_name(step)
    success = Map.get(payload, :success, true)

    content = extract_step_content(payload)

    content_str = content

    Conversations.touch_run(run_id)

    persist_event(%{
      run_id: run_id,
      conversation_id: conversation_id,
      event_type: "tool_result",
      tool_name: tool_name,
      tool_success: success,
      content: String.slice(content_str, 0, 10_000)
    })

    Session.broadcast(
      run_id,
      {:tool_result,
       %{
         tool: tool_name,
         success: success,
         summary: String.slice(content_str, 0, 200),
         content: String.slice(content_str, 0, 50_000),
         run_id: run_id
       }}
    )

    # Persist validation result incrementally on the API
    persist_validation_result(step, success, payload, api_id, org_id)

    # When planning step completes, create placeholder files in DB and notify LiveView
    if step == :planning_files do
      case Map.get(payload, :manifest) do
        files when is_list(files) ->
          StreamManager.create_manifest_placeholders(api_id, org_id, files)
          Session.broadcast(run_id, {:manifest_ready, %{manifest: files}})

        _ ->
          :ok
      end
    end
  end

  def translate_pipeline_event(
        {:step_failed, %{step: step, error: error}},
        run_id,
        conversation_id,
        api_id,
        org_id
      ) do
    tool_name = step_to_tool_name(step)

    persist_event(%{
      run_id: run_id,
      conversation_id: conversation_id,
      event_type: "tool_result",
      tool_name: tool_name,
      tool_success: false,
      content: error
    })

    Session.broadcast(
      run_id,
      {:tool_result,
       %{
         tool: tool_name,
         success: false,
         summary: String.slice(error, 0, 200),
         content: error,
         run_id: run_id
       }}
    )

    # Persist validation failure incrementally
    persist_validation_result(step, false, %{content: error}, api_id, org_id)
  end

  # Multi-file pipeline events: track current file and forward to LiveView
  def translate_pipeline_event({:file_started, payload}, run_id, _, api_id, org_id) do
    # Flush any remaining stream from previous file
    StreamManager.flush_remaining_stream(run_id)

    # Save accumulated content of PREVIOUS file before switching
    StreamManager.save_accumulated_file_content(api_id, org_id)

    # Now switch to the new file
    path = Map.get(payload, :path)
    Process.put(:current_streaming_file, path)
    Process.put(:current_streaming_content, "")

    Session.broadcast(run_id, {:file_started, payload})
  end

  def translate_pipeline_event({:file_completed, payload}, run_id, _, api_id, org_id) do
    StreamManager.flush_remaining_stream(run_id)

    # Save the completed file content to DB
    path = Map.get(payload, :path) || Process.get(:current_streaming_file)
    accumulated = Process.get(:current_streaming_content, "")

    if path && accumulated != "" do
      StreamManager.save_file_content_to_db(api_id, org_id, path, accumulated)
    end

    Process.put(:current_streaming_file, nil)
    Process.put(:current_streaming_content, "")

    Session.broadcast(run_id, {:file_completed, payload})
  end

  def translate_pipeline_event(_event, _run_id, _conversation_id, _api_id, _org_id), do: :ok

  @spec persist_event(map()) :: :ok
  def persist_event(attrs) do
    seq = Conversations.next_sequence(attrs.run_id)

    case Conversations.append_event(Map.put(attrs, :sequence, seq)) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Failed to persist event: #{inspect(changeset.errors)}")
        :ok
    end
  end

  @spec persist_validation_result(atom(), boolean(), map(), String.t(), String.t()) :: :ok
  def persist_validation_result(step, success, payload, api_id, org_id) do
    case step_to_validation_attrs(step, success, payload) do
      nil ->
        :ok

      attrs ->
        api = Apis.get_api(org_id, api_id)

        if api do
          current = api.validation_report || %{}
          updated = Map.merge(current, attrs)
          Apis.update_api(api, %{validation_report: updated})
        end

        :ok
    end
  rescue
    e ->
      Logger.warning("Failed to persist validation result: #{Exception.message(e)}")
      :ok
  end

  @spec step_to_validation_attrs(atom(), boolean(), map()) :: map() | nil
  def step_to_validation_attrs(:formatting, true, _payload) do
    %{"format" => "pass", "format_issues" => []}
  end

  def step_to_validation_attrs(:formatting, false, %{content: error}) do
    %{"format" => "fail", "format_issues" => [error]}
  end

  def step_to_validation_attrs(:compiling, true, _payload) do
    %{"compilation" => "pass", "compilation_errors" => []}
  end

  def step_to_validation_attrs(:compiling, false, %{content: errors}) do
    %{"compilation" => "fail", "compilation_errors" => String.split(errors, "\n")}
  end

  def step_to_validation_attrs(:linting, success, %{content: content}) do
    status = if success, do: "pass", else: "fail"
    issues = if success, do: [], else: String.split(content, "\n")
    %{"credo" => status, "credo_issues" => issues}
  end

  def step_to_validation_attrs(:running_tests, success, %{content: content}) do
    status = if success, do: "pass", else: "fail"
    # Parse test results from content for structured data
    test_results = parse_test_results_from_content(content)
    %{"tests" => status, "test_results" => test_results}
  end

  def step_to_validation_attrs(:submitting, _success, _payload) do
    %{"overall" => "pass"}
  end

  # Fix/retry steps and others don't update validation
  def step_to_validation_attrs(_step, _success, _payload), do: nil

  @spec parse_test_results_from_content(String.t()) :: [map()]
  def parse_test_results_from_content(content) do
    content
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      cond do
        String.starts_with?(String.trim(line), "✓ ") ->
          name = String.trim(line) |> String.trim_leading("✓ ")
          [%{"name" => name, "status" => "passed"} | acc]

        String.starts_with?(String.trim(line), "FAIL: ") ->
          name = String.trim(line) |> String.trim_leading("FAIL: ")
          [%{"name" => name, "status" => "failed"} | acc]

        true ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  @spec step_to_tool_name(atom()) :: String.t()
  def step_to_tool_name(:generating_code), do: "generate_code"
  def step_to_tool_name(:formatting), do: "format_code"
  def step_to_tool_name(:compiling), do: "compile_code"
  def step_to_tool_name(:linting), do: "lint_code"
  def step_to_tool_name(:fixing_compilation), do: "compile_code"
  def step_to_tool_name(:fixing_lint), do: "lint_code"
  def step_to_tool_name(:generating_tests), do: "generate_tests"
  def step_to_tool_name(:generating_docs), do: "generate_docs"
  def step_to_tool_name(:running_tests), do: "run_tests"
  def step_to_tool_name(:fixing_tests), do: "run_tests"
  def step_to_tool_name(:submitting), do: "submit_code"
  def step_to_tool_name(:planning_files), do: "plan_files"
  def step_to_tool_name(:generating_helpers), do: "generate_helpers"
  def step_to_tool_name(_), do: "unknown"

  # ── Private helpers ────────────────────────────────────────────

  @spec extract_step_content(map()) :: String.t()
  defp extract_step_content(%{manifest: files}) when is_list(files) and files != [] do
    Enum.map_join(files, ", ", &(&1["path"] || ""))
  end

  defp extract_step_content(payload) do
    [:content, :code, :test_code]
    |> Enum.find_value("", fn key ->
      case Map.get(payload, key) do
        c when is_binary(c) and c != "" -> c
        _ -> nil
      end
    end)
  end
end
