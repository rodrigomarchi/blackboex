defmodule Blackboex.Agent.Session do
  @moduledoc """
  GenServer that orchestrates a single agent run.

  Lifecycle:
  1. KickoffWorker creates Conversation + Run in DB, then starts this GenServer
  2. GenServer builds LLMChain with tools + callbacks
  3. Chain runs via Task.async_nolink (non-blocking)
  4. LangChain callbacks persist Events and broadcast PubSub
  5. Guardrails checked after each tool execution via callbacks
  6. On submit_code: saves results, creates ApiVersion, updates Api
  7. On failure/guardrail: saves partial results, marks run as failed/partial
  8. GenServer terminates after completion
  """

  use GenServer

  require Logger

  alias Blackboex.Agent.CodePipeline
  alias Blackboex.Apis
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.Conversations
  alias Blackboex.LLM.CircuitBreaker
  alias Blackboex.Organizations
  alias Blackboex.Telemetry.Events

  @type start_opts :: %{
          run_id: String.t(),
          api_id: String.t(),
          conversation_id: String.t(),
          run_type: String.t(),
          trigger_message: String.t(),
          user_id: String.t() | integer(),
          organization_id: String.t(),
          current_code: String.t() | nil,
          current_tests: String.t() | nil
        }

  @type t :: %__MODULE__{
          run_id: String.t() | nil,
          api_id: String.t() | nil,
          conversation_id: String.t() | nil,
          run_type: String.t() | nil,
          trigger_message: String.t() | nil,
          user_id: String.t() | integer() | nil,
          organization_id: String.t() | nil,
          current_code: String.t() | nil,
          current_tests: String.t() | nil,
          task_ref: reference() | nil,
          timeout_timer: reference() | nil
        }

  defstruct [
    :run_id,
    :api_id,
    :conversation_id,
    :run_type,
    :trigger_message,
    :user_id,
    :organization_id,
    :current_code,
    :current_tests,
    :task_ref,
    :timeout_timer
  ]

  # ── Client API ─────────────────────────────────────────────────

  @doc "Starts an agent session under the SessionSupervisor."
  @spec start(start_opts()) :: {:ok, pid()} | {:error, term()}
  def start(opts) do
    DynamicSupervisor.start_child(
      Blackboex.Agent.SessionSupervisor,
      {__MODULE__, opts}
    )
  end

  @doc false
  @spec start_link(start_opts()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via(opts.run_id))
  end

  @spec child_spec(start_opts()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, opts.run_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 30_000
    }
  end

  # ── Server ─────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    state = %__MODULE__{
      run_id: opts.run_id,
      api_id: opts.api_id,
      conversation_id: opts.conversation_id,
      run_type: opts.run_type,
      trigger_message: opts.trigger_message,
      user_id: opts.user_id,
      organization_id: opts.organization_id,
      current_code: opts[:current_code],
      current_tests: opts[:current_tests],
      timeout_timer: nil
    }

    send(self(), :start_chain)
    {:ok, state}
  end

  @impl true
  def handle_info(:start_chain, state) do
    if CircuitBreaker.allow?(:anthropic) do
      start_chain_execution(state)
    else
      handle_circuit_open(state)
      {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({ref, {:ok, chain_result}}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    if state.timeout_timer, do: Process.cancel_timer(state.timeout_timer)
    handle_chain_success(state, chain_result)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({ref, {:error, error}}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    if state.timeout_timer, do: Process.cancel_timer(state.timeout_timer)
    handle_chain_failure(state, error)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    if state.timeout_timer, do: Process.cancel_timer(state.timeout_timer)
    handle_chain_failure(state, {:crashed, reason})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:task_timeout, state) do
    Logger.warning("Agent task timeout (7 min) for run #{state.run_id}, marking as failed")
    Events.emit_session_timeout(%{run_id: state.run_id})
    handle_chain_failure(state, "Agent task exceeded 7-minute timeout")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:retries_exceeded, state) do
    Logger.warning("LLM retries exceeded for run #{state.run_id}")
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Chain Execution ────────────────────────────────────────────

  defp start_chain_execution(state) do
    run = Conversations.get_run!(state.run_id)
    Conversations.update_run_metrics(run, %{started_at: DateTime.utc_now()})
    mark_run_as_running(run)

    # Reset validation_report for the new run
    api = Apis.get_api(state.organization_id, state.api_id)
    if api, do: Apis.update_api(api, %{validation_report: %{}})

    broadcast(state.run_id, {:agent_started, %{run_id: state.run_id, run_type: state.run_type}})

    task =
      Task.Supervisor.async_nolink(Blackboex.SandboxTaskSupervisor, fn ->
        run_chain(state)
      end)

    timer_ref = Process.send_after(self(), :task_timeout, :timer.minutes(7))
    {:noreply, %{state | task_ref: task.ref, timeout_timer: timer_ref}}
  end

  @spec mark_run_as_running(Blackboex.Conversations.Run.t()) ::
          {:ok, Blackboex.Conversations.Run.t()}
  defp mark_run_as_running(run) do
    case Conversations.complete_run(run, %{status: "running"}) do
      {:ok, r} -> {:ok, r}
      {:error, _} -> {:ok, run}
    end
  end

  @spec run_chain(t()) :: {:ok, map()} | {:error, term()}
  defp run_chain(state) do
    api = Apis.get_api(state.organization_id, state.api_id)

    if is_nil(api) do
      {:error, :api_not_found}
    else
      broadcast_fn = build_broadcast_fn(state)

      opts = [
        broadcast_fn: broadcast_fn,
        run_id: state.run_id,
        conversation_id: state.conversation_id,
        token_callback: build_token_callback(state.run_id)
      ]

      case state.run_type do
        "edit" ->
          source_files = Apis.get_source_for_compilation(api.id)
          test_files = Apis.get_tests_for_running(api.id)
          current_code = state.current_code || Enum.map_join(source_files, "\n\n", & &1.content)
          current_tests = state.current_tests || Enum.map_join(test_files, "\n\n", & &1.content)

          CodePipeline.run_edit(
            api,
            state.trigger_message,
            current_code,
            current_tests,
            opts
          )

        _generation ->
          CodePipeline.run_generation(api, state.trigger_message, opts)
      end
    end
  end

  @spec build_token_callback(String.t()) :: (String.t() -> :ok)
  defp build_token_callback(run_id) do
    fn token ->
      buffer = Process.get(:stream_buffer, "")
      new_buffer = buffer <> token

      if String.length(new_buffer) >= 20 or String.contains?(token, "\n") do
        Process.put(:stream_buffer, "")

        Phoenix.PubSub.broadcast(
          Blackboex.PubSub,
          "run:#{run_id}",
          {:agent_streaming, %{delta: new_buffer}}
        )
      else
        Process.put(:stream_buffer, new_buffer)
      end

      :ok
    end
  end

  @spec flush_remaining_stream(String.t()) :: :ok
  defp flush_remaining_stream(run_id) do
    buffer = Process.get(:stream_buffer, "")

    if buffer != "" do
      Process.put(:stream_buffer, "")

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "run:#{run_id}",
        {:agent_streaming, %{delta: buffer}}
      )
    end

    :ok
  end

  @spec build_broadcast_fn(t()) :: (term() -> :ok)
  defp build_broadcast_fn(state) do
    run_id = state.run_id
    conversation_id = state.conversation_id
    api_id = state.api_id
    organization_id = state.organization_id

    fn event ->
      translate_pipeline_event(event, run_id, conversation_id, api_id, organization_id)
    end
  end

  @spec translate_pipeline_event(term(), String.t(), String.t(), String.t(), String.t()) :: :ok
  defp translate_pipeline_event(
         {:step_started, %{step: step}},
         run_id,
         conversation_id,
         _api_id,
         _org_id
       ) do
    flush_remaining_stream(run_id)
    tool_name = step_to_tool_name(step)

    persist_event(%{
      run_id: run_id,
      conversation_id: conversation_id,
      event_type: "tool_call",
      tool_name: tool_name,
      tool_input: %{}
    })

    broadcast(run_id, {:agent_action, %{tool: tool_name, args: %{}, run_id: run_id}})
  end

  defp translate_pipeline_event(
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

    broadcast(
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
  end

  defp translate_pipeline_event(
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

    broadcast(
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

  defp translate_pipeline_event(_event, _run_id, _conversation_id, _api_id, _org_id), do: :ok

  @spec extract_step_content(map()) :: String.t()
  defp extract_step_content(payload) do
    [:content, :code, :test_code]
    |> Enum.find_value("", fn key ->
      case Map.get(payload, key) do
        c when is_binary(c) and c != "" -> c
        _ -> nil
      end
    end)
  end

  # ── Incremental Validation Persistence ─────────────────────────

  @spec persist_validation_result(atom(), boolean(), map(), String.t(), String.t()) :: :ok
  defp persist_validation_result(step, success, payload, api_id, org_id) do
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
  defp step_to_validation_attrs(:formatting, true, _payload) do
    %{"format" => "pass", "format_issues" => []}
  end

  defp step_to_validation_attrs(:formatting, false, %{content: error}) do
    %{"format" => "fail", "format_issues" => [error]}
  end

  defp step_to_validation_attrs(:compiling, true, _payload) do
    %{"compilation" => "pass", "compilation_errors" => []}
  end

  defp step_to_validation_attrs(:compiling, false, %{content: errors}) do
    %{"compilation" => "fail", "compilation_errors" => String.split(errors, "\n")}
  end

  defp step_to_validation_attrs(:linting, success, %{content: content}) do
    status = if success, do: "pass", else: "fail"
    issues = if success, do: [], else: String.split(content, "\n")
    %{"credo" => status, "credo_issues" => issues}
  end

  defp step_to_validation_attrs(:running_tests, success, %{content: content}) do
    status = if success, do: "pass", else: "fail"
    # Parse test results from content for structured data
    test_results = parse_test_results_from_content(content)
    %{"tests" => status, "test_results" => test_results}
  end

  defp step_to_validation_attrs(:submitting, _success, _payload) do
    %{"overall" => "pass"}
  end

  # Fix/retry steps and others don't update validation
  defp step_to_validation_attrs(_step, _success, _payload), do: nil

  @spec parse_test_results_from_content(String.t()) :: [map()]
  defp parse_test_results_from_content(content) do
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

  @spec register_and_extract_schema(String.t(), String.t()) :: :ok
  defp register_and_extract_schema(api_id, org_id) do
    api = Apis.get_api(org_id, api_id)
    do_register_module(api, org_id)
  rescue
    e ->
      Logger.error(
        "Failed to register module for API #{api_id}: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      :ok
  end

  @spec do_register_module(Blackboex.Apis.Api.t() | nil, String.t()) :: :ok
  defp do_register_module(nil, _org_id), do: :ok

  defp do_register_module(api, org_id) do
    source_files = Apis.get_source_for_compilation(api.id)

    if source_files == [] do
      :ok
    else
      compile_and_register(api, source_files, org_id)
    end
  end

  defp compile_and_register(api, source_files, org_id) do
    case Compiler.compile_files(api, source_files) do
      {:ok, module} ->
        org = Organizations.get_organization(org_id)
        org_slug = if(org, do: org.slug, else: "")
        Apis.Registry.register(api.id, module, org_slug: org_slug, slug: api.slug)
        schema_attrs = extract_schema_attrs(module)
        Apis.update_api(api, Map.merge(%{status: "compiled"}, schema_attrs))
        :ok

      {:error, reason} ->
        Logger.warning("Failed to compile for registry: #{inspect(reason)}")
        :ok
    end
  end

  @spec extract_schema_attrs(module()) :: map()
  defp extract_schema_attrs(module) do
    alias Blackboex.CodeGen.SchemaExtractor

    case SchemaExtractor.extract(module) do
      {:ok, %{request: req, response: resp} = schema} ->
        %{
          param_schema: SchemaExtractor.to_param_schema(schema),
          example_request: if(req, do: SchemaExtractor.generate_example(req), else: nil),
          example_response: if(resp, do: SchemaExtractor.generate_example(resp), else: nil)
        }

      {:error, _} ->
        %{}
    end
  rescue
    e ->
      Logger.warning("Schema extraction failed: #{Exception.message(e)}")
      %{}
  end

  @spec step_to_tool_name(atom()) :: String.t()
  defp step_to_tool_name(:generating_code), do: "generate_code"
  defp step_to_tool_name(:formatting), do: "format_code"
  defp step_to_tool_name(:compiling), do: "compile_code"
  defp step_to_tool_name(:linting), do: "lint_code"
  defp step_to_tool_name(:fixing_compilation), do: "compile_code"
  defp step_to_tool_name(:fixing_lint), do: "lint_code"
  defp step_to_tool_name(:generating_tests), do: "generate_tests"
  defp step_to_tool_name(:generating_docs), do: "generate_docs"
  defp step_to_tool_name(:running_tests), do: "run_tests"
  defp step_to_tool_name(:fixing_tests), do: "run_tests"
  defp step_to_tool_name(:submitting), do: "submit_code"
  defp step_to_tool_name(_), do: "unknown"

  @spec persist_event(map()) :: :ok
  defp persist_event(attrs) do
    seq = Conversations.next_sequence(attrs.run_id)

    case Conversations.append_event(Map.put(attrs, :sequence, seq)) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Failed to persist event: #{inspect(changeset.errors)}")
        :ok
    end
  end

  # ── Result Handling ────────────────────────────────────────────

  @spec handle_chain_success(t(), map()) :: :ok
  defp handle_chain_success(state, result) do
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
      register_and_extract_schema(state.api_id, state.organization_id)
    end

    update_conversation_stats(state)
    persist_completion_event(state, result, status)
    emit_run_telemetry(state, run, status)

    broadcast(state.run_id, {
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

  @spec save_api_and_version(t(), Blackboex.Conversations.Run.t(), map(), String.t()) ::
          :ok | term()
  defp save_api_and_version(state, run, result, status) do
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
  defp update_api_from_result(api, result, status) do
    gen_status = if status == "completed", do: "completed", else: "partial"

    attrs =
      %{generation_status: gen_status, generation_error: nil}
      |> maybe_put(:documentation_md, result[:documentation_md])

    Apis.upsert_files(api, files_from_result(result), %{source: "generation"})
    Apis.update_api(api, attrs)
  end

  @spec files_from_result(map()) :: [map()]
  defp files_from_result(result) do
    files = [%{path: "/src/handler.ex", content: result[:code], file_type: "source"}]

    files =
      if result[:test_code] do
        files ++
          [%{path: "/test/handler_test.ex", content: result[:test_code], file_type: "test"}]
      else
        files
      end

    if result[:documentation_md] do
      files ++ [%{path: "/README.md", content: result[:documentation_md], file_type: "doc"}]
    else
      files
    end
  end

  @spec maybe_create_version(
          Blackboex.Apis.Api.t(),
          Blackboex.Conversations.Run.t(),
          t(),
          map(),
          String.t()
        ) ::
          :ok | term()
  defp maybe_create_version(_api, _run, _state, _result, status) when status != "completed",
    do: :ok

  defp maybe_create_version(api, run, state, _result, _status) do
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

  @spec persist_completion_event(t(), map(), String.t()) :: :ok | {:ok, term()} | {:error, term()}
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

  @spec handle_chain_failure(t(), term()) :: :ok
  defp handle_chain_failure(state, error) do
    run = Conversations.get_run!(state.run_id)
    error_msg = format_error(error)

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

    broadcast(state.run_id, {
      :agent_failed,
      %{error: error_msg, run_id: state.run_id}
    })

    Logger.warning("Agent session failed for run #{state.run_id}: #{error_msg}")
  end

  @spec handle_circuit_open(t()) :: :ok
  defp handle_circuit_open(state) do
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

    broadcast(state.run_id, {
      :agent_failed,
      %{error: "LLM provider temporarily unavailable", run_id: state.run_id}
    })
  end

  # ── Helpers ────────────────────────────────────────────────────

  @spec update_conversation_stats(t()) :: :ok | term()
  defp update_conversation_stats(state) do
    conversation = Conversations.get_conversation(state.conversation_id)

    if conversation do
      Conversations.increment_conversation_stats(conversation, total_runs: 1)
    end
  end

  @spec emit_run_telemetry(t(), Blackboex.Conversations.Run.t(), String.t()) :: :ok
  defp emit_run_telemetry(state, run, status) do
    Events.emit_agent_run(%{
      run_id: state.run_id,
      run_type: state.run_type,
      status: status,
      duration_ms: run.duration_ms || 0,
      iteration_count: run.iteration_count,
      cost_cents: run.cost_cents
    })
  end

  @spec format_error(term()) :: String.t()
  defp format_error({:crashed, reason}), do: "Agent process crashed: #{inspect(reason)}"
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  @spec broadcast(String.t(), term()) :: :ok
  defp broadcast(run_id, message) do
    case Phoenix.PubSub.broadcast(Blackboex.PubSub, "run:#{run_id}", message) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("PubSub broadcast failed for run #{run_id}: #{inspect(reason)}")
        :ok
    end
  end

  @spec via(String.t()) :: {:via, Registry, {Blackboex.Agent.SessionRegistry, String.t()}}
  defp via(run_id), do: {:via, Registry, {Blackboex.Agent.SessionRegistry, run_id}}
end
