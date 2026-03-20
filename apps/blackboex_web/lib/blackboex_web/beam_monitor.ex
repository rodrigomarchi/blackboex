defmodule BlackboexWeb.BeamMonitor do
  @moduledoc """
  Periodically scans BEAM processes for high message queue lengths.

  When a process exceeds the configured threshold, logs a warning and
  emits a `[:blackboex, :beam, :high_message_queue]` telemetry event.

  If the system has more than 50_000 processes, a random sample is
  checked instead of the full list to avoid performance impact.
  """

  use GenServer

  require Logger

  @default_interval :timer.seconds(30)
  @default_threshold 10_000
  @sample_limit 50_000
  @sample_size 10_000

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec check_now() :: :ok
  def check_now do
    GenServer.cast(__MODULE__, :check)
  end

  # Server callbacks

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    threshold = Keyword.get(opts, :threshold, @default_threshold)

    state = %{
      interval: interval,
      threshold: threshold
    }

    schedule_check(interval)
    {:ok, state}
  end

  @impl true
  def handle_info(:check, state) do
    scan_processes(state.threshold)
    schedule_check(state.interval)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(:check, state) do
    scan_processes(state.threshold)
    {:noreply, state}
  end

  # Private

  defp schedule_check(interval) do
    Process.send_after(self(), :check, interval)
  end

  defp scan_processes(threshold) do
    process_count = :erlang.system_info(:process_count)
    pids = Process.list()

    pids_to_check =
      if process_count > @sample_limit do
        pids |> Enum.shuffle() |> Enum.take(@sample_size)
      else
        pids
      end

    Enum.each(pids_to_check, fn pid ->
      check_process(pid, threshold)
    end)
  rescue
    error ->
      Logger.warning("BeamMonitor scan failed: #{Exception.message(error)}")
  end

  defp check_process(pid, threshold) do
    case :erlang.process_info(pid, :message_queue_len) do
      {:message_queue_len, len} when len >= threshold ->
        report_high_queue(pid, len)

      _ ->
        :ok
    end
  end

  defp report_high_queue(pid, queue_len) do
    info = process_details(pid)

    Logger.warning(
      "High message queue detected: " <>
        "pid=#{inspect(pid)} " <>
        "name=#{info.name} " <>
        "queue_len=#{queue_len} " <>
        "current_function=#{inspect(info.current_function)}"
    )

    :telemetry.execute(
      [:blackboex, :beam, :high_message_queue],
      %{queue_len: queue_len},
      %{
        pid: pid,
        name: info.name,
        current_function: info.current_function
      }
    )
  end

  defp process_details(pid) do
    name =
      case :erlang.process_info(pid, :registered_name) do
        {:registered_name, name} -> name
        _ -> nil
      end

    current_function =
      case :erlang.process_info(pid, :current_function) do
        {:current_function, mfa} -> mfa
        _ -> nil
      end

    %{name: name, current_function: current_function}
  end
end
