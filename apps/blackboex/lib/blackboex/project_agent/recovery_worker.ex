defmodule Blackboex.ProjectAgent.RecoveryWorker do
  @moduledoc ~S"""
  Oban cron worker that polls `:running` `PlanTask` rows and drives them
  to terminal via `BroadcastAdapter.handle_terminal/4`.

  Runs every minute via the Oban cron plugin.

  ## Per-invocation logic

  For every `PlanTask` with `status: "running"` and a non-nil `child_run_id`:

  1. Resolve the child run from the appropriate `*Conversations.get_run/1`
     based on `artifact_type`.
  2. If the child run is **terminal** (`completed`/`failed`/`canceled`/
     `cancelled`): call `BroadcastAdapter.handle_terminal/4` with the
     appropriate status.
  3. If the child run is **stale** — still `"running"` or `"pending"` but
     `updated_at` older than `@stale_threshold_ms` — call
     `BroadcastAdapter.handle_terminal/4` with `:failed`.
  4. Otherwise (child run is pending/running and not yet stale): no-op.
  5. If the child run row cannot be found: call
     `BroadcastAdapter.handle_terminal/4` with `:failed` so the plan does
     not stall forever.

  `handle_terminal/4` is idempotent, so running this worker multiple times
  for the same terminal task is safe.
  """

  use Oban.Worker,
    queue: :project_orchestration,
    max_attempts: 1

  require Logger

  alias Blackboex.Conversations
  alias Blackboex.FlowConversations
  alias Blackboex.PageConversations
  alias Blackboex.Plans
  alias Blackboex.Plans.PlanTask
  alias Blackboex.PlaygroundConversations
  alias Blackboex.ProjectAgent.BroadcastAdapter
  alias Blackboex.Repo

  # Tasks running for more than 15 minutes are considered stale.
  @stale_threshold_ms 900_000

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{}) do
    tasks = Plans.list_running_tasks()

    if tasks != [] do
      Logger.info("ProjectAgent.RecoveryWorker: polling #{length(tasks)} running task(s)")
    end

    Enum.each(tasks, &check_task/1)

    :ok
  end

  @spec check_task(PlanTask.t()) :: :ok
  defp check_task(%PlanTask{child_run_id: child_run_id, artifact_type: type} = task)
       when is_binary(child_run_id) do
    plan = Repo.preload(task, :plan).plan

    case resolve_child_run(type, child_run_id) do
      nil ->
        Logger.warning(
          "ProjectAgent.RecoveryWorker: child run #{child_run_id} not found for task #{task.id}, failing task"
        )

        BroadcastAdapter.handle_terminal(task, plan, :failed, "child_run_not_found")

      run ->
        handle_child_run(run, task, plan)
    end
  end

  defp check_task(%PlanTask{id: id}) do
    Logger.warning("ProjectAgent.RecoveryWorker: task #{id} has no child_run_id, skipping")
    :ok
  end

  @spec handle_child_run(map(), PlanTask.t(), map()) :: :ok
  defp handle_child_run(run, task, plan) do
    cond do
      terminal_status?(run.status) ->
        translated = translate_status(run.status)
        error = if translated == :failed, do: child_run_error(run), else: nil
        BroadcastAdapter.handle_terminal(task, plan, translated, error)

      stale?(run) ->
        Logger.warning(
          "ProjectAgent.RecoveryWorker: child run is stale (last updated #{run.updated_at}), failing task #{task.id}"
        )

        BroadcastAdapter.handle_terminal(task, plan, :failed, "stale: child run timed out")

      true ->
        :ok
    end
  end

  @spec child_run_error(map()) :: String.t() | nil
  defp child_run_error(run) do
    Map.get(run, :error_message) || Map.get(run, :error_summary)
  end

  @spec resolve_child_run(String.t(), Ecto.UUID.t()) :: map() | nil
  defp resolve_child_run("api", run_id), do: Conversations.get_run(run_id)
  defp resolve_child_run("flow", run_id), do: FlowConversations.get_run(run_id)
  defp resolve_child_run("page", run_id), do: PageConversations.get_run(run_id)
  defp resolve_child_run("playground", run_id), do: PlaygroundConversations.get_run(run_id)

  defp resolve_child_run(type, run_id) do
    Logger.warning(
      "ProjectAgent.RecoveryWorker: unknown artifact_type #{inspect(type)} for run #{run_id}"
    )

    nil
  end

  @terminal_statuses ~w(completed failed canceled cancelled)

  @spec terminal_status?(String.t()) :: boolean()
  defp terminal_status?(status), do: status in @terminal_statuses

  @spec translate_status(String.t()) :: BroadcastAdapter.terminal_status()
  defp translate_status("completed"), do: :completed
  defp translate_status(_failed_or_canceled), do: :failed

  @spec stale?(map()) :: boolean()
  defp stale?(%{updated_at: updated_at}) when not is_nil(updated_at) do
    # Per-artifact Run schemas use either `:utc_datetime` (DateTime) or the
    # default `:naive_datetime` (NaiveDateTime); normalize before diffing.
    diff_ms =
      case updated_at do
        %DateTime{} -> DateTime.diff(DateTime.utc_now(), updated_at, :millisecond)
        %NaiveDateTime{} -> NaiveDateTime.diff(NaiveDateTime.utc_now(), updated_at, :millisecond)
      end

    diff_ms > @stale_threshold_ms
  end

  defp stale?(_run), do: false
end
