defmodule Blackboex.FlowAgent.KickoffWorker do
  @moduledoc """
  Oban worker that bootstraps a FlowAgent run.

  Responsibilities (in order):

    1. Get-or-create the `FlowConversation`
    2. Create a `FlowRun` record (status `"pending"`)
    3. Persist the initial `user_message` event (sequence 0)
    4. Broadcast `:run_started` to the flow topic
    5. Start the `FlowAgent.Session` GenServer

  Unique constraint prevents duplicate runs for the same flow within 30s.
  """

  use Oban.Worker,
    queue: :flow_agent,
    max_attempts: 1,
    unique: [keys: [:flow_id], period: 30]

  require Logger

  alias Blackboex.FlowAgent.Session
  alias Blackboex.FlowAgent.StreamManager
  alias Blackboex.FlowConversations

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "flow_id" => flow_id,
      "organization_id" => organization_id,
      "project_id" => project_id,
      "user_id" => user_id,
      "run_type" => run_type,
      "trigger_message" => trigger_message
    } = args

    definition_before = Map.get(args, "definition_before", %{})
    pre_run_id = Map.get(args, "run_id")

    with {:ok, conversation} <-
           FlowConversations.get_or_create_active_conversation(
             flow_id,
             organization_id,
             project_id
           ),
         {:ok, run} <-
           FlowConversations.create_run(
             %{
               conversation_id: conversation.id,
               flow_id: flow_id,
               organization_id: organization_id,
               user_id: user_id,
               run_type: run_type,
               status: "pending",
               trigger_message: trigger_message,
               definition_before: definition_before
             },
             pre_run_id
           ),
         {:ok, _event} <-
           FlowConversations.append_event(run, %{
             sequence: 0,
             event_type: "user_message",
             content: trigger_message
           }) do
      StreamManager.broadcast_flow(
        flow_id,
        {:run_started, %{run_id: run.id, run_type: run_type, flow_id: flow_id}}
      )

      case Session.start(%{
             run_id: run.id,
             flow_id: flow_id,
             conversation_id: conversation.id,
             organization_id: organization_id,
             project_id: project_id,
             user_id: user_id,
             run_type: String.to_existing_atom(run_type),
             trigger_message: trigger_message,
             definition_before: definition_before
           }) do
        {:ok, _pid} ->
          Logger.info("FlowAgent session started for run #{run.id} (#{run_type})")
          :ok

        {:error, reason} ->
          Logger.error("Failed to start flow agent session: #{inspect(reason)}")
          {:ok, _} = FlowConversations.fail_run(run, "session_start_failed")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("FlowAgent kickoff failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end
