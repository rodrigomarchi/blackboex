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

  alias Blackboex.Agent.Session.ChainRunner
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
      ChainRunner.handle_circuit_open(state)
      {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({ref, {:ok, chain_result}}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    if state.timeout_timer, do: Process.cancel_timer(state.timeout_timer)
    ChainRunner.handle_chain_success(state, chain_result)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({ref, {:error, error}}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    if state.timeout_timer, do: Process.cancel_timer(state.timeout_timer)
    ChainRunner.handle_chain_failure(state, error)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    if state.timeout_timer, do: Process.cancel_timer(state.timeout_timer)
    ChainRunner.handle_chain_failure(state, {:crashed, reason})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:task_timeout, state) do
    Logger.warning("Agent task timeout (7 min) for run #{state.run_id}, marking as failed")
    Events.emit_session_timeout(%{run_id: state.run_id})
    ChainRunner.handle_chain_failure(state, "Agent task exceeded 7-minute timeout")
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
        ChainRunner.run_chain(state)
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

  # ── Helpers ────────────────────────────────────────────────────

  @spec format_error(term()) :: String.t()
  def format_error({:crashed, reason}), do: "Agent process crashed: #{inspect(reason)}"
  def format_error(%{message: msg}) when is_binary(msg), do: msg
  def format_error(error) when is_binary(error), do: error
  def format_error(error), do: inspect(error)

  @spec broadcast(String.t(), term()) :: :ok
  def broadcast(run_id, message) do
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
