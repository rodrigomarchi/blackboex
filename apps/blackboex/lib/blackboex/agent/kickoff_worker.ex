defmodule Blackboex.Agent.KickoffWorker do
  @moduledoc """
  Oban worker that creates the Conversation/Run records and starts an Agent.Session.

  This is the entry point for all agent executions — both initial generation
  and chat edits. It ensures durable state exists in the DB before starting
  the ephemeral GenServer.
  """

  use Oban.Worker,
    queue: :generation,
    max_attempts: 5,
    unique: [keys: [:api_id, :run_type], period: 30]

  require Logger

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Progressive backoff: 1min, 2min, 5min, 10min
    Enum.at([60, 120, 300, 600], attempt - 1, 600)
  end

  alias Blackboex.Agent.Session
  alias Blackboex.Conversations

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "api_id" => api_id,
      "organization_id" => organization_id,
      "user_id" => user_id,
      "run_type" => run_type,
      "trigger_message" => trigger_message
    } = args

    current_code = Map.get(args, "current_code")
    current_tests = Map.get(args, "current_tests")

    # 1. Get or create conversation
    {:ok, conversation} = Conversations.get_or_create_conversation(api_id, organization_id)

    # 2. Create run record
    {:ok, run} =
      Conversations.create_run(%{
        conversation_id: conversation.id,
        api_id: api_id,
        user_id: user_id,
        organization_id: organization_id,
        run_type: run_type,
        status: "pending",
        trigger_message: trigger_message,
        config: %{
          "max_iterations" => 15,
          "max_time_ms" => 300_000,
          "max_cost_cents" => 50
        },
        model: "claude-sonnet-4-20250514"
      })

    # 3. Persist initial user message event
    {:ok, _event} =
      Conversations.append_event(%{
        run_id: run.id,
        conversation_id: conversation.id,
        event_type: "user_message",
        sequence: 0,
        role: "user",
        content: trigger_message
      })

    # 4. Broadcast that a run is starting (LiveView subscribes to api topic)
    Phoenix.PubSub.broadcast(
      Blackboex.PubSub,
      "api:#{api_id}",
      {:agent_run_started, %{run_id: run.id, run_type: run_type}}
    )

    # 5. Start the Agent Session GenServer
    case Session.start(%{
           run_id: run.id,
           api_id: api_id,
           conversation_id: conversation.id,
           run_type: run_type,
           trigger_message: trigger_message,
           user_id: user_id,
           organization_id: organization_id,
           current_code: current_code,
           current_tests: current_tests
         }) do
      {:ok, _pid} ->
        Logger.info("Agent session started for run #{run.id} (#{run_type})")
        :ok

      {:error, reason} ->
        Logger.error("Failed to start agent session for run #{run.id}: #{inspect(reason)}")

        Conversations.complete_run(run, %{
          status: "failed",
          error_summary: "Failed to start agent session: #{inspect(reason)}"
        })

        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(7)
end
