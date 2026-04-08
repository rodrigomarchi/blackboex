defmodule Blackboex.Agent.Session.ChainRunner do
  @moduledoc """
  Handles chain execution result processing for Agent.Session.
  """

  require Logger

  alias Blackboex.Agent.CodePipeline
  alias Blackboex.Agent.Session
  alias Blackboex.Agent.Session.SchemaRegistration
  alias Blackboex.Agent.Session.StreamManager
  alias Blackboex.Apis
  alias Blackboex.Conversations
  alias Blackboex.Telemetry.Events

  @spec run_chain(Blackboex.Agent.Session.t()) :: {:ok, map()} | {:error, term()}
  def run_chain(state) do
    api = Apis.get_api(state.organization_id, state.api_id)

    if is_nil(api) do
      {:error, :api_not_found}
    else
      broadcast_fn = StreamManager.build_broadcast_fn(state)

      opts = [
        broadcast_fn: broadcast_fn,
        run_id: state.run_id,
        conversation_id: state.conversation_id,
        token_callback: StreamManager.build_token_callback(state.run_id)
      ]

      case state.run_type do
        "edit" -> run_edit_pipeline(api, state, opts)
        _generation -> CodePipeline.run_multi_file_generation(api, state.trigger_message, opts)
      end
    end
  end

  @spec run_edit_pipeline(Blackboex.Apis.Api.t(), Blackboex.Agent.Session.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run_edit_pipeline(api, state, opts) do
    source_files = Apis.get_source_for_compilation(api.id)
    test_files = Apis.get_tests_for_running(api.id)

    current_files =
      Enum.map(source_files, &%{path: &1.path, content: &1.content, file_type: "source"})

    current_test_files =
      Enum.map(test_files, &%{path: &1.path, content: &1.content, file_type: "test"})

    CodePipeline.run_multi_file_edit(
      api,
      state.trigger_message,
      current_files,
      current_test_files,
      opts
    )
  end

  @spec handle_chain_success(Blackboex.Agent.Session.t(), map()) :: :ok
  def handle_chain_success(state, result) do
    run = Conversations.get_run!(state.run_id)
    status = if Map.get(result, :partial, false), do: "partial", else: "completed"

    {:ok, run} =
      Conversations.complete_run(run, %{
        status: status,
        final_code: result[:code],
        final_test_code: result[:test_code],
        run_summary: result[:summary] || "Completed",
        error_summary: nil
      })

    # Persist LLM usage metrics and event count on the run
    usage = result[:usage] || %{}
    event_count = Conversations.next_sequence(state.run_id)

    Conversations.update_run_metrics(run, %{
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      event_count: event_count
    })

    save_api_and_version(state, run, result, status)

    # Register compiled module and extract schema (must run after save_api_and_version
    # because it reads api.source_code from DB which is updated there)
    if status == "completed" do
      SchemaRegistration.register_and_extract_schema(
        state.api_id,
        state.organization_id
      )
    end

    update_conversation_stats(state)
    persist_completion_event(state, result, status)
    emit_run_telemetry(state, run, status)

    Session.broadcast(state.run_id, {
      :agent_completed,
      %{
        code: result[:code],
        test_code: result[:test_code],
        summary: result[:summary],
        run_id: state.run_id,
        status: status
      }
    })

    Logger.info("Agent session completed for run #{state.run_id} with status #{status}")
  end

  @spec handle_chain_failure(Blackboex.Agent.Session.t(), term()) :: :ok
  def handle_chain_failure(state, error) do
    run = Conversations.get_run!(state.run_id)
    error_msg = Session.format_error(error)

    Conversations.complete_run(run, %{
      status: "failed",
      error_summary: error_msg
    })

    api = Apis.get_api(state.organization_id, state.api_id)

    if api do
      current_report = api.validation_report || %{}
      failed_report = Map.put(current_report, "overall", "fail")

      Apis.update_api(api, %{
        generation_status: "failed",
        generation_error: String.slice(error_msg, 0, 5000),
        validation_report: failed_report
      })
    end

    update_conversation_stats(state)

    Conversations.append_event(%{
      run_id: state.run_id,
      conversation_id: state.conversation_id,
      event_type: "status_change",
      sequence: Conversations.next_sequence(state.run_id),
      content: "failed",
      metadata: %{"error" => error_msg}
    })

    emit_run_telemetry(state, run, "failed")

    Session.broadcast(state.run_id, {
      :agent_failed,
      %{error: error_msg, run_id: state.run_id}
    })

    Logger.warning("Agent session failed for run #{state.run_id}: #{error_msg}")
  end

  @spec handle_circuit_open(Blackboex.Agent.Session.t()) :: :ok
  def handle_circuit_open(state) do
    run = Conversations.get_run!(state.run_id)

    Conversations.complete_run(run, %{
      status: "failed",
      error_summary: "LLM provider circuit breaker is open. Please try again later."
    })

    Conversations.append_event(%{
      run_id: state.run_id,
      conversation_id: state.conversation_id,
      event_type: "error",
      sequence: 0,
      content: "Circuit breaker open for LLM provider"
    })

    Session.broadcast(state.run_id, {
      :agent_failed,
      %{error: "LLM provider temporarily unavailable", run_id: state.run_id}
    })
  end

  @spec save_api_and_version(
          Blackboex.Agent.Session.t(),
          Blackboex.Conversations.Run.t(),
          map(),
          String.t()
        ) ::
          :ok | term()
  def save_api_and_version(state, run, result, status) do
    api = Apis.get_api(state.organization_id, state.api_id)

    cond do
      is_nil(api) ->
        :ok

      result[:code] ->
        case update_api_from_result(api, result, status) do
          {:ok, updated_api} ->
            maybe_create_version(updated_api, run, state, result, status)

          {:error, reason} ->
            Logger.warning("Failed to update API #{state.api_id}: #{inspect(reason)}")
        end

      true ->
        gen_status = if status == "completed", do: "completed", else: "partial"
        Apis.update_api(api, %{generation_status: gen_status, generation_error: nil})
    end
  end

  @spec update_api_from_result(Blackboex.Apis.Api.t(), map(), String.t()) ::
          {:ok, Blackboex.Apis.Api.t()} | {:error, Ecto.Changeset.t()}
  def update_api_from_result(api, result, status) do
    gen_status = if status == "completed", do: "completed", else: "partial"

    attrs =
      %{generation_status: gen_status, generation_error: nil}
      |> maybe_put(:documentation_md, result[:documentation_md])

    Apis.upsert_files(api, files_from_result(result), %{source: "generation"})
    Apis.update_api(api, attrs)
  end

  @spec maybe_create_version(
          Blackboex.Apis.Api.t(),
          Blackboex.Conversations.Run.t(),
          Blackboex.Agent.Session.t(),
          map(),
          String.t()
        ) ::
          :ok | term()
  def maybe_create_version(_api, _run, _state, _result, status) when status != "completed",
    do: :ok

  def maybe_create_version(api, run, state, _result, _status) do
    version_source = if state.run_type == "generation", do: "generation", else: "chat_edit"

    case Apis.create_version(api, %{
           source: version_source,
           prompt: state.trigger_message,
           compilation_status: "success",
           created_by_id: state.user_id
         }) do
      {:ok, version} ->
        Conversations.complete_run(run, %{api_version_id: version.id})

      {:error, reason} ->
        Logger.warning("Failed to create version for run #{state.run_id}: #{inspect(reason)}")
    end
  end

  @spec update_conversation_stats(Blackboex.Agent.Session.t()) :: :ok | term()
  def update_conversation_stats(state) do
    conversation = Conversations.get_conversation(state.conversation_id)

    if conversation do
      Conversations.increment_conversation_stats(conversation, total_runs: 1)
    end
  end

  @spec emit_run_telemetry(
          Blackboex.Agent.Session.t(),
          Blackboex.Conversations.Run.t(),
          String.t()
        ) :: :ok
  def emit_run_telemetry(state, run, status) do
    Events.emit_agent_run(%{
      run_id: state.run_id,
      run_type: state.run_type,
      status: status,
      duration_ms: run.duration_ms || 0,
      iteration_count: run.iteration_count,
      cost_cents: run.cost_cents
    })
  end

  # ── Private helpers ────────────────────────────────────────────

  @spec files_from_result(map()) :: [map()]
  defp files_from_result(result) do
    source_files = result[:files] || []
    test_files = result[:test_files] || []
    all_files = source_files ++ test_files

    if result[:documentation_md] do
      all_files ++ [%{path: "/README.md", content: result[:documentation_md], file_type: "doc"}]
    else
      all_files
    end
  end

  @spec persist_completion_event(Blackboex.Agent.Session.t(), map(), String.t()) ::
          :ok | {:ok, term()} | {:error, term()}
  defp persist_completion_event(state, result, status) do
    Conversations.append_event(%{
      run_id: state.run_id,
      conversation_id: state.conversation_id,
      event_type: "status_change",
      sequence: Conversations.next_sequence(state.run_id),
      content: status,
      metadata: %{"summary" => result[:summary] || ""}
    })
  end

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
