defmodule Blackboex.PlaygroundAgent.KickoffWorker do
  @moduledoc """
  Oban worker that bootstraps a PlaygroundAgent run.

  Responsibilities (in order):
  1. Get-or-create the `PlaygroundConversation`
  2. Create a `PlaygroundRun` record (status `"pending"`)
  3. Persist the initial `user_message` event (sequence 0)
  4. Broadcast `:run_started` to the playground topic
  5. Start the `PlaygroundAgent.Session` GenServer

  Unique constraint prevents duplicate runs for the same playground within 30s.
  """

  use Oban.Worker,
    queue: :playground_agent,
    max_attempts: 1,
    unique: [keys: [:playground_id], period: 30]

  require Logger

  alias Blackboex.PlaygroundAgent.Session
  alias Blackboex.PlaygroundAgent.StreamManager
  alias Blackboex.PlaygroundConversations

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "playground_id" => playground_id,
      "organization_id" => organization_id,
      "project_id" => project_id,
      "user_id" => user_id,
      "run_type" => run_type,
      "trigger_message" => trigger_message
    } = args

    code_before = Map.get(args, "code_before", "")

    with {:ok, conversation} <-
           PlaygroundConversations.get_or_create_active_conversation(
             playground_id,
             organization_id,
             project_id
           ),
         {:ok, run} <-
           PlaygroundConversations.create_run(%{
             conversation_id: conversation.id,
             playground_id: playground_id,
             organization_id: organization_id,
             user_id: user_id,
             run_type: run_type,
             status: "pending",
             trigger_message: trigger_message,
             code_before: code_before
           }),
         {:ok, _event} <-
           PlaygroundConversations.append_event(run, %{
             sequence: 0,
             event_type: "user_message",
             content: trigger_message
           }) do
      StreamManager.broadcast_playground(
        playground_id,
        {:run_started, %{run_id: run.id, run_type: run_type, playground_id: playground_id}}
      )

      case Session.start(%{
             run_id: run.id,
             playground_id: playground_id,
             conversation_id: conversation.id,
             organization_id: organization_id,
             project_id: project_id,
             user_id: user_id,
             run_type: String.to_existing_atom(run_type),
             trigger_message: trigger_message,
             code_before: code_before
           }) do
        {:ok, _pid} ->
          Logger.info("PlaygroundAgent session started for run #{run.id} (#{run_type})")
          :ok

        {:error, reason} ->
          Logger.error("Failed to start playground agent session: #{inspect(reason)}")
          {:ok, _} = PlaygroundConversations.fail_run(run, "session_start_failed")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("PlaygroundAgent kickoff failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end
