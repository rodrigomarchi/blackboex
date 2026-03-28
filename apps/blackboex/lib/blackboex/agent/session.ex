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

  alias Blackboex.Agent.{Callbacks, CodeGenChain, EditChain, Guardrails}
  alias Blackboex.Apis
  alias Blackboex.Conversations
  alias Blackboex.LLM.CircuitBreaker
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
    :guardrail_config
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
      guardrail_config: Guardrails.default_config()
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
    handle_chain_success(state, chain_result)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({ref, {:error, error}}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    handle_chain_failure(state, error)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    handle_chain_failure(state, {:crashed, reason})
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

    broadcast(state.run_id, {:agent_started, %{run_id: state.run_id, run_type: state.run_type}})

    task =
      Task.Supervisor.async_nolink(Blackboex.SandboxTaskSupervisor, fn ->
        run_chain(state)
      end)

    {:noreply, %{state | task_ref: task.ref}}
  end

  defp mark_run_as_running(run) do
    case Conversations.complete_run(run, %{status: "running"}) do
      {:ok, r} -> {:ok, r}
      {:error, _} -> {:ok, run}
    end
  end

  defp run_chain(state) do
    api = Apis.get_api(state.organization_id, state.api_id)

    if is_nil(api) do
      {:error, :api_not_found}
    else
      chain = build_chain(state, api)
      execute_chain(chain, state)
    end
  end

  defp build_chain(state, api) do
    session_ctx = %{
      run_id: state.run_id,
      conversation_id: state.conversation_id,
      session_pid: self()
    }

    context = %{api: api, sandbox_opts: [timeout: 30_000]}
    opts = [context: context, session_ctx: session_ctx, stream: true]

    case state.run_type do
      "edit" ->
        EditChain.build(
          state.trigger_message,
          Keyword.merge(opts,
            current_code: state.current_code || api.source_code || "",
            current_tests: state.current_tests || api.test_code || "",
            conversation_id: state.conversation_id
          )
        )

      _generation ->
        CodeGenChain.build(state.trigger_message, opts)
    end
  end

  defp execute_chain(chain, state) do
    case run_with_guardrails(chain, state) do
      {:ok, _chain, tool_result} ->
        {:ok, extract_submit_result(tool_result)}

      {:error, _chain, error} ->
        {:error, error}

      {:guardrail, reason, last_code} ->
        {:ok, %{code: last_code, test_code: nil, summary: "Guardrail: #{reason}", partial: true}}
    end
  end

  defp run_with_guardrails(chain, state) do
    # Use the appropriate runner based on run_type.
    # Both CodeGenChain.run and EditChain.run call LLMChain.run_until_tool_used
    # with the same signature, so the dispatch is about which module to call.
    runner = chain_runner(state.run_type)

    case runner.run(chain) do
      {:ok, _chain, _tool_result} = success ->
        success

      {:error, chain, %LangChain.LangChainError{} = error} ->
        if String.contains?(inspect(error), "max_runs") do
          force_submit(chain, state)
        else
          {:error, chain, error}
        end

      {:error, _chain, _error} = failure ->
        failure
    end
  end

  defp chain_runner("edit"), do: EditChain
  defp chain_runner(_), do: CodeGenChain

  defp force_submit(chain, state) do
    Callbacks.persist_guardrail_event(
      state.run_id,
      state.conversation_id,
      :max_iterations
    )

    last_code = extract_last_code_from_chain(chain)

    if last_code do
      {:guardrail, :max_iterations, last_code}
    else
      run = Conversations.get_run!(state.run_id)

      Conversations.complete_run(run, %{
        status: "failed",
        error_summary: "Agent exceeded maximum iterations without submitting code"
      })

      {:error, chain, :max_iterations_no_code}
    end
  end

  # ── Result Handling ────────────────────────────────────────────

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

    save_api_and_version(state, run, result, status)
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

  defp save_api_and_version(state, run, result, status) do
    api = Apis.get_api(state.organization_id, state.api_id)

    if api && result[:code] do
      case update_api_from_result(api, result, status) do
        {:ok, updated_api} ->
          maybe_create_version(updated_api, run, state, result, status)

        {:error, reason} ->
          Logger.warning("Failed to update API #{state.api_id}: #{inspect(reason)}")
      end
    end
  end

  defp update_api_from_result(api, result, status) do
    gen_status = if status == "completed", do: "completed", else: "partial"

    attrs =
      %{source_code: result[:code], generation_status: gen_status, generation_error: nil}
      |> maybe_put(:test_code, result[:test_code])

    Apis.update_api(api, attrs)
  end

  defp maybe_create_version(_api, _run, _state, _result, status) when status != "completed",
    do: :ok

  defp maybe_create_version(api, run, state, result, _status) do
    version_source = if state.run_type == "generation", do: "generation", else: "chat_edit"

    case Apis.create_version(api, %{
           code: result[:code],
           test_code: result[:test_code],
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp handle_chain_failure(state, error) do
    run = Conversations.get_run!(state.run_id)
    error_msg = format_error(error)

    Conversations.complete_run(run, %{
      status: "failed",
      error_summary: error_msg
    })

    api = Apis.get_api(state.organization_id, state.api_id)

    if api do
      Apis.update_api(api, %{
        generation_status: "failed",
        generation_error: String.slice(error_msg, 0, 5000)
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

  defp extract_submit_result(tool_result) do
    # LangChain's run_until_tool_used returns the ToolResult struct.
    # The arguments that were passed TO the tool are in the ToolCall,
    # which is accessible via the tool_result or chain messages.
    args =
      cond do
        is_struct(tool_result) and Map.has_key?(tool_result, :arguments) ->
          tool_result.arguments || %{}

        is_struct(tool_result) and Map.has_key?(tool_result, :call_arguments) ->
          tool_result.call_arguments || %{}

        is_map(tool_result) ->
          tool_result

        true ->
          %{}
      end

    %{
      code: Map.get(args, "code"),
      test_code: Map.get(args, "test_code"),
      summary: Map.get(args, "summary", "Completed")
    }
  end

  defp extract_last_code_from_chain(chain) do
    chain.messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg ->
      with true <- is_map(msg),
           name when name in ["compile_code", "format_code", "submit_code"] <-
             Map.get(msg, :tool_name) || Map.get(msg, :name),
           args when is_map(args) <- Map.get(msg, :arguments) do
        Map.get(args, "code")
      else
        _ -> nil
      end
    end)
  end

  defp update_conversation_stats(state) do
    conversation = Conversations.get_conversation(state.conversation_id)

    if conversation do
      Conversations.increment_conversation_stats(conversation, total_runs: 1)
    end
  end

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

  defp format_error({:crashed, reason}), do: "Agent process crashed: #{inspect(reason)}"
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp broadcast(run_id, message) do
    Phoenix.PubSub.broadcast(Blackboex.PubSub, "run:#{run_id}", message)
  end

  defp via(run_id), do: {:via, Registry, {Blackboex.Agent.SessionRegistry, run_id}}
end
