defmodule Blackboex.PlaygroundAgent.Session do
  @moduledoc """
  GenServer orchestrating a single Playground AI run.

  Lifecycle:
  1. KickoffWorker creates PlaygroundConversation + PlaygroundRun, then starts this GenServer
  2. GenServer checks the LLM circuit breaker
  3. ChainRunner is invoked in `Task.Supervisor.async_nolink` (non-blocking)
  4. CodePipeline calls the LLM with streaming, emitting `:code_delta` events
  5. On success: `Playgrounds.record_ai_edit` updates the playground + snapshot
  6. On failure/timeout: run marked as failed, `:run_failed` broadcast
  7. GenServer terminates after completion
  """

  use GenServer

  require Logger

  alias Blackboex.LLM.CircuitBreaker
  alias Blackboex.PlaygroundAgent.ChainRunner
  alias Blackboex.PlaygroundConversations

  @session_timeout_ms :timer.minutes(3)

  @type start_opts :: %{
          run_id: String.t(),
          playground_id: String.t(),
          conversation_id: String.t(),
          organization_id: String.t(),
          project_id: String.t() | nil,
          user_id: String.t() | integer(),
          run_type: :generate | :edit,
          trigger_message: String.t(),
          code_before: String.t()
        }

  @type t :: %__MODULE__{
          run_id: String.t() | nil,
          playground_id: String.t() | nil,
          conversation_id: String.t() | nil,
          organization_id: String.t() | nil,
          project_id: String.t() | nil,
          user_id: String.t() | integer() | nil,
          run_type: :generate | :edit | nil,
          trigger_message: String.t() | nil,
          code_before: String.t() | nil,
          task_ref: reference() | nil,
          timeout_timer: reference() | nil
        }

  defstruct [
    :run_id,
    :playground_id,
    :conversation_id,
    :organization_id,
    :project_id,
    :user_id,
    :run_type,
    :trigger_message,
    :code_before,
    :task_ref,
    :timeout_timer
  ]

  # ── Client API ─────────────────────────────────────────────

  @spec start(start_opts()) :: DynamicSupervisor.on_start_child()
  def start(opts) do
    DynamicSupervisor.start_child(
      Blackboex.PlaygroundAgent.SessionSupervisor,
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
      shutdown: 10_000
    }
  end

  # ── Server ─────────────────────────────────────────────────

  @impl true
  def init(opts) do
    state = %__MODULE__{
      run_id: opts.run_id,
      playground_id: opts.playground_id,
      conversation_id: opts.conversation_id,
      organization_id: opts.organization_id,
      project_id: Map.get(opts, :project_id),
      user_id: opts.user_id,
      run_type: opts.run_type,
      trigger_message: opts.trigger_message,
      code_before: opts.code_before || ""
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
    cancel_timer(state.timeout_timer)
    ChainRunner.handle_chain_success(state, chain_result)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({ref, {:error, error}}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    cancel_timer(state.timeout_timer)
    ChainRunner.handle_chain_failure(state, error)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    cancel_timer(state.timeout_timer)
    ChainRunner.handle_chain_failure(state, {:crashed, reason})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:task_timeout, state) do
    Logger.warning("PlaygroundAgent task timeout for run #{state.run_id}")
    ChainRunner.handle_chain_failure(state, "Agente excedeu o timeout de 3 minutos")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Chain execution ────────────────────────────────────────

  defp start_chain_execution(state) do
    run = PlaygroundConversations.get_run!(state.run_id)
    {:ok, _} = PlaygroundConversations.mark_run_running(run)

    task =
      Task.Supervisor.async_nolink(Blackboex.SandboxTaskSupervisor, fn ->
        ChainRunner.run_chain(state)
      end)

    timer = Process.send_after(self(), :task_timeout, @session_timeout_ms)
    {:noreply, %{state | task_ref: task.ref, timeout_timer: timer}}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  @spec via(String.t()) ::
          {:via, Registry, {Blackboex.PlaygroundAgent.SessionRegistry, String.t()}}
  defp via(run_id), do: {:via, Registry, {Blackboex.PlaygroundAgent.SessionRegistry, run_id}}
end
