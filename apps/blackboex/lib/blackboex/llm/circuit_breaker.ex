defmodule Blackboex.LLM.CircuitBreaker do
  @moduledoc """
  Circuit breaker for LLM providers.

  Tracks per-provider health with three states:
  - `:closed` (healthy) — requests pass through
  - `:open` (broken) — requests fail immediately
  - `:half_open` (testing) — allows a probe request through

  Transitions:
  - closed → open: after `failure_threshold` failures within `failure_window_ms`
  - open → half_open: after `recovery_timeout_ms`
  - half_open → closed: after `success_threshold` consecutive successes
  - half_open → open: on any failure
  """

  use GenServer

  require Logger

  @type state :: :closed | :open | :half_open
  @type provider :: atom()

  @failure_threshold 5
  @failure_window_ms 60_000
  @recovery_timeout_ms 30_000
  @success_threshold 2

  # ── Client API ─────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns true if requests to the given provider are allowed (circuit not open)."
  @spec allow?(provider()) :: boolean()
  def allow?(provider) do
    GenServer.call(__MODULE__, {:allow?, provider})
  end

  @doc "Records a successful call to the provider."
  @spec record_success(provider()) :: :ok
  def record_success(provider) do
    GenServer.cast(__MODULE__, {:success, provider})
  end

  @doc "Records a failed call to the provider."
  @spec record_failure(provider()) :: :ok
  def record_failure(provider) do
    GenServer.cast(__MODULE__, {:failure, provider})
  end

  @doc "Returns the current circuit breaker state for a provider."
  @spec get_state(provider()) :: state()
  def get_state(provider) do
    GenServer.call(__MODULE__, {:get_state, provider})
  end

  @doc "Resets the circuit breaker for a provider to closed state."
  @spec reset(provider()) :: :ok
  def reset(provider) do
    GenServer.cast(__MODULE__, {:reset, provider})
  end

  # ── Server ─────────────────────────────────────────────────────

  defmodule ProviderState do
    @moduledoc false
    defstruct state: :closed,
              failures: [],
              consecutive_successes: 0,
              opened_at: nil
  end

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    {:ok, %{providers: %{}}}
  end

  @impl true
  def handle_call({:allow?, provider}, _from, state) do
    %ProviderState{} = ps = get_provider_state(state, provider)

    case ps.state do
      :closed ->
        {:reply, true, state}

      :open ->
        if should_transition_to_half_open?(ps) do
          new_provider = %{ps | state: :half_open}
          new_state = put_provider_state(state, provider, new_provider)

          Logger.info("Circuit breaker half-open for provider #{provider}")

          {:reply, true, new_state}
        else
          {:reply, false, state}
        end

      :half_open ->
        {:reply, true, state}
    end
  end

  def handle_call({:get_state, provider}, _from, state) do
    {:reply, get_provider_state(state, provider).state, state}
  end

  @impl true
  def handle_cast({:success, provider}, state) do
    %ProviderState{} = ps = get_provider_state(state, provider)

    new_provider =
      case ps.state do
        :half_open ->
          new_count = ps.consecutive_successes + 1

          if new_count >= @success_threshold do
            Logger.info("Circuit breaker closed for provider #{provider}")

            %ProviderState{state: :closed, failures: [], consecutive_successes: 0, opened_at: nil}
          else
            %{ps | consecutive_successes: new_count}
          end

        :closed ->
          %{ps | failures: [], consecutive_successes: 0}

        _other ->
          ps
      end

    {:noreply, put_provider_state(state, provider, new_provider)}
  end

  def handle_cast({:failure, provider}, state) do
    %ProviderState{} = ps = get_provider_state(state, provider)

    new_provider =
      case ps.state do
        :closed ->
          now = System.monotonic_time(:millisecond)
          cutoff = now - @failure_window_ms
          recent_failures = [now | Enum.filter(ps.failures, &(&1 >= cutoff))]

          if length(recent_failures) >= @failure_threshold do
            Logger.warning("Circuit breaker opened for provider #{provider}")

            %ProviderState{
              state: :open,
              failures: recent_failures,
              consecutive_successes: 0,
              opened_at: now
            }
          else
            %{ps | failures: recent_failures}
          end

        :half_open ->
          Logger.warning("Circuit breaker re-opened for provider #{provider}")

          %ProviderState{
            state: :open,
            failures: [],
            consecutive_successes: 0,
            opened_at: System.monotonic_time(:millisecond)
          }

        :open ->
          ps
      end

    {:noreply, put_provider_state(state, provider, new_provider)}
  end

  def handle_cast({:reset, provider}, state) do
    {:noreply, put_provider_state(state, provider, %ProviderState{})}
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp get_provider_state(state, provider) do
    Map.get(state.providers, provider, %ProviderState{})
  end

  defp put_provider_state(state, provider, provider_state) do
    %{state | providers: Map.put(state.providers, provider, provider_state)}
  end

  defp should_transition_to_half_open?(%ProviderState{opened_at: nil}), do: false

  defp should_transition_to_half_open?(%ProviderState{opened_at: opened_at}) do
    now = System.monotonic_time(:millisecond)
    now - opened_at >= @recovery_timeout_ms
  end
end
