defmodule Blackboex.FlowAgent.KickoffWorkerTest do
  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  # KickoffWorker.perform/1 starts a FlowAgent.Session whose async chain task
  # may finish after the test exits, logging benign sandbox-owner errors.
  @moduletag :capture_log

  import Mox

  alias Blackboex.FlowAgent.KickoffWorker
  alias Blackboex.FlowConversations

  setup :set_mox_global
  setup :stub_llm_client
  setup [:create_user_and_org]

  defp base_args(%{user: user, org: org}) do
    flow = flow_fixture(%{user: user, org: org})

    {flow,
     %{
       "flow_id" => flow.id,
       "organization_id" => org.id,
       "project_id" => flow.project_id,
       "user_id" => user.id,
       "run_type" => "edit",
       "trigger_message" => "adicione um delay",
       "definition_before" => %{}
     }}
  end

  describe "perform/1" do
    test "creates conversation, run, user_message event, and broadcasts :run_started", ctx do
      {flow, args} = base_args(ctx)
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_agent:flow:#{flow.id}")

      assert :ok = perform_job(KickoffWorker, args)

      conv = FlowConversations.get_active_conversation(flow.id)
      assert conv
      assert conv.flow_id == flow.id

      [run] = FlowConversations.list_runs(conv.id)
      assert run.run_type == "edit"
      assert run.status in ["pending", "running", "completed", "failed"]

      [event | _] = FlowConversations.list_events(run.id)
      assert event.sequence == 0
      assert event.event_type == "user_message"
      assert event.content == "adicione um delay"

      assert_receive {:run_started, %{run_id: rid, flow_id: fid}}, 500
      assert rid == run.id
      assert fid == flow.id
    end

    test "reuses active conversation on second perform", ctx do
      {flow, args} = base_args(ctx)
      assert :ok = perform_job(KickoffWorker, args)
      conv_first = FlowConversations.get_active_conversation(flow.id)

      assert :ok = perform_job(KickoffWorker, args)
      conv_second = FlowConversations.get_active_conversation(flow.id)

      assert conv_first.id == conv_second.id
      assert length(FlowConversations.list_runs(conv_first.id)) == 2
    end
  end

  describe "worker config" do
    test "is declared unique on :flow_id for 30s" do
      assert KickoffWorker.__opts__()[:unique] == [keys: [:flow_id], period: 30]
      assert KickoffWorker.__opts__()[:queue] == :flow_agent
      assert KickoffWorker.__opts__()[:max_attempts] == 1
    end

    test "timeout is 5 minutes" do
      assert KickoffWorker.timeout(%Oban.Job{}) == :timer.minutes(5)
    end
  end
end
