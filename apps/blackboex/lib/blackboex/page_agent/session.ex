defmodule Blackboex.PageAgent.Session do
  @moduledoc """
  GenServer orchestrating a single Page AI editor run.

  Lifecycle:
  1. KickoffWorker creates PageConversation + PageRun, then starts this GenServer
  2. GenServer checks the LLM circuit breaker
  3. ChainRunner runs the markdown pipeline in `Task.Supervisor.async_nolink`
  4. ContentPipeline calls the LLM with streaming, emitting `:content_delta`
  5. On success: `Pages.record_ai_edit` updates the page's content
  6. On failure/timeout: run marked as failed, `:run_failed` broadcast
  7. GenServer terminates after completion
  """

  use GenServer

  require Logger

  alias Blackboex.LLM.CircuitBreaker
  alias Blackboex.PageAgent.ChainRunner
  alias Blackboex.PageConversations

  @session_timeout_ms :timer.minutes(3)

  @type start_opts :: %{
          run_id: String.t(),
          page_id: String.t(),
          conversation_id: String.t(),
          organization_id: String.t(),
          project_id: String.t() | nil,
          user_id: String.t() | integer(),
          run_type: :generate | :edit,
          trigger_message: String.t(),
          content_before: String.t()
        }

  @type t :: %__MODULE__{
          run_id: String.t() | nil,
          page_id: String.t() | nil,
          conversation_id: String.t() | nil,
          organization_id: String.t() | nil,
          project_id: String.t() | nil,
          user_id: String.t() | integer() | nil,
          run_type: :generate | :edit | nil,
          trigger_message: String.t() | nil,
          content_before: String.t() | nil,
          task_ref: reference() | nil,
          task_pid: pid() | nil,
          timeout_timer: reference() | nil
        }

  defstruct [
    :run_id,
    :page_id,
    :conversation_id,
    :organization_id,
    :project_id,
    :user_id,
    :run_type,
    :trigger_message,
    :content_before,
    :task_ref,
    :task_pid,
    :timeout_timer
  ]

  # ── Client API ─────────────────────────────────────────────

  @spec start(start_opts()) :: DynamicSupervisor.on_start_child()
  def start(opts) do
    DynamicSupervisor.start_child(
      Blackboex.PageAgent.SessionSupervisor,
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
      page_id: opts.page_id,
      conversation_id: opts.conversation_id,
      organization_id: opts.organization_id,
      project_id: Map.get(opts, :project_id),
      user_id: opts.user_id,
      run_type: opts.run_type,
      trigger_message: opts.trigger_message,
      content_before: opts.content_before || ""
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
    Logger.warning("PageAgent task timeout for run #{state.run_id}")
    kill_task(state)
    ChainRunner.handle_chain_failure(state, "Agent exceeded the 3-minute timeout")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp start_chain_execution(state) do
    run = PageConversations.get_run!(state.run_id)
    {:ok, _} = PageConversations.mark_run_running(run)

    task =
      Task.Supervisor.async_nolink(Blackboex.SandboxTaskSupervisor, fn ->
        ChainRunner.run_chain(state)
      end)

    timer = Process.send_after(self(), :task_timeout, @session_timeout_ms)
    {:noreply, %{state | task_ref: task.ref, task_pid: task.pid, timeout_timer: timer}}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  # On timeout the GenServer is about to stop; the spawned task is unlinked
  # (`async_nolink`) and would otherwise outlive us, holding the LLM stream and
  # a DB connection. Kill it explicitly so the resources are reclaimed.
  defp kill_task(%{task_pid: nil}), do: :ok

  defp kill_task(%{task_pid: pid}) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    :ok
  end

  @spec via(String.t()) :: {:via, Registry, {Blackboex.PageAgent.SessionRegistry, String.t()}}
  defp via(run_id), do: {:via, Registry, {Blackboex.PageAgent.SessionRegistry, run_id}}
end
