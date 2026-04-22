defmodule Blackboex.PageAgent.KickoffWorker do
  @moduledoc """
  Oban worker that bootstraps a PageAgent run.

  Responsibilities (in order):
  1. Get-or-create the active `PageConversation`
  2. Create a `PageRun` record (status `"pending"`)
  3. Persist the initial `user_message` event (sequence 0)
  4. Broadcast `:run_started` on the per-page PubSub topic
  5. Start the `PageAgent.Session` GenServer

  Unique constraint prevents duplicate runs for the same page within 30s.
  """

  use Oban.Worker,
    queue: :page_agent,
    max_attempts: 1,
    unique: [keys: [:page_id], period: 30]

  require Logger

  alias Blackboex.PageAgent.Session
  alias Blackboex.PageAgent.StreamManager
  alias Blackboex.PageConversations
  alias Blackboex.Pages

  @run_types %{"generate" => :generate, "edit" => :edit}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "page_id" => page_id,
      "organization_id" => organization_id,
      "project_id" => project_id,
      "user_id" => user_id,
      "run_type" => run_type_str,
      "trigger_message" => trigger_message
    } = args

    run_type = Map.get(@run_types, run_type_str, :edit)

    # Read content fresh from the DB (not from Oban args) so we always see
    # the latest content even if the job sat in the queue.
    case Pages.get_for_org(organization_id, page_id) do
      nil ->
        Logger.warning("PageAgent kickoff: page #{page_id} not found, cancelling job")
        {:cancel, :page_not_found}

      page ->
        do_perform(page, %{
          page_id: page_id,
          organization_id: organization_id,
          project_id: project_id,
          user_id: user_id,
          run_type: run_type,
          run_type_str: run_type_str,
          trigger_message: trigger_message,
          content_before: page.content || ""
        })
    end
  end

  defp do_perform(_page, ctx) do
    with {:ok, conversation} <-
           PageConversations.get_or_create_active_conversation(
             ctx.page_id,
             ctx.organization_id,
             ctx.project_id
           ),
         {:ok, run} <-
           PageConversations.create_run(%{
             conversation_id: conversation.id,
             page_id: ctx.page_id,
             organization_id: ctx.organization_id,
             user_id: ctx.user_id,
             run_type: ctx.run_type_str,
             status: "pending",
             trigger_message: ctx.trigger_message,
             content_before: ctx.content_before
           }),
         {:ok, _event} <-
           PageConversations.append_event(run, %{
             sequence: 0,
             event_type: "user_message",
             content: ctx.trigger_message
           }) do
      StreamManager.broadcast_page(
        ctx.organization_id,
        ctx.page_id,
        {:run_started,
         %{
           run_id: run.id,
           run_type: ctx.run_type_str,
           page_id: ctx.page_id
         }}
      )

      case Session.start(%{
             run_id: run.id,
             page_id: ctx.page_id,
             conversation_id: conversation.id,
             organization_id: ctx.organization_id,
             user_id: ctx.user_id,
             run_type: ctx.run_type,
             trigger_message: ctx.trigger_message,
             content_before: ctx.content_before
           }) do
        {:ok, _pid} ->
          Logger.info("PageAgent session started for run #{run.id} (#{ctx.run_type_str})")
          :ok

        {:error, reason} ->
          Logger.error("Failed to start page agent session: #{inspect(reason)}")
          {:ok, _} = PageConversations.fail_run(run, "session_start_failed")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("PageAgent kickoff failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end
