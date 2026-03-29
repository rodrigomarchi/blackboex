defmodule Blackboex.Agent.RecoveryWorker do
  @moduledoc """
  Oban cron worker that detects stale runs and marks them as failed.

  A run is "stale" if it has status "running" but hasn't been updated
  in over 2 minutes — meaning the Agent.Session GenServer died without
  completing the run (node crash, deploy, OOM, etc.).

  Runs every 2 minutes.
  """

  use Oban.Worker,
    queue: :generation,
    max_attempts: 1

  require Logger

  alias Blackboex.Apis
  alias Blackboex.Conversations

  @stale_after_ms 300_000

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    stale_runs = Conversations.list_stale_runs(@stale_after_ms)

    if stale_runs != [] do
      Logger.info("RecoveryWorker found #{length(stale_runs)} stale run(s)")
    end

    Enum.each(stale_runs, &recover_run/1)

    :ok
  end

  defp recover_run(run) do
    Logger.warning("Marking stale run #{run.id} as failed (last updated: #{run.updated_at})")

    Conversations.complete_run(run, %{
      status: "failed",
      error_summary: "Run timed out — agent session was lost (node crash or deploy)"
    })

    # Persist a status_change event
    Conversations.append_event(%{
      run_id: run.id,
      conversation_id: run.conversation_id,
      event_type: "status_change",
      sequence: Conversations.next_sequence(run.id),
      content: "failed",
      metadata: %{"reason" => "stale_recovery", "stale_after_ms" => @stale_after_ms}
    })

    # Update API generation_status so it doesn't stay stuck on "generating"
    if run.api_id do
      case Apis.get_api(run.organization_id, run.api_id) do
        nil -> :ok
        api -> Apis.update_api(api, %{generation_status: "failed", generation_error: "Session lost"})
      end
    end

    # Notify LiveView
    Phoenix.PubSub.broadcast(
      Blackboex.PubSub,
      "run:#{run.id}",
      {:agent_failed, %{error: "Session lost — please try again", run_id: run.id}}
    )

    Phoenix.PubSub.broadcast(
      Blackboex.PubSub,
      "api:#{run.api_id}",
      {:agent_failed, %{error: "Session lost — please try again", run_id: run.id}}
    )
  end
end
