defmodule Blackboex.PageAgent.KickoffWorkerTest do
  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  @moduletag :integration

  alias Blackboex.LLM.ClientMock
  alias Blackboex.PageAgent.KickoffWorker
  alias Blackboex.PageAgent.StreamManager
  alias Blackboex.PageConversations

  setup do
    {user, org} = user_and_org_fixture()
    page = page_fixture(%{user: user, org: org})

    Phoenix.PubSub.subscribe(
      Blackboex.PubSub,
      StreamManager.page_topic(org.id, page.id)
    )

    args = %{
      "page_id" => page.id,
      "organization_id" => org.id,
      "project_id" => page.project_id,
      "user_id" => user.id,
      "run_type" => "edit",
      "trigger_message" => "do the thing"
    }

    Mox.stub(ClientMock, :stream_text, fn _, _ -> {:error, :no_stub} end)
    Mox.stub(ClientMock, :generate_text, fn _, _ -> {:error, :no_stub} end)
    Mox.set_mox_global()

    %{user: user, org: org, page: page, args: args}
  end

  describe "perform/1" do
    test "creates conversation, run, user_message event, broadcasts, starts Session", %{
      args: args,
      page: page
    } do
      assert :ok = perform_job(KickoffWorker, args)

      # conversation exists
      conv = PageConversations.get_active_conversation(page.id)
      assert conv

      # one run with user_message event
      [run] = PageConversations.list_runs(conv.id)
      assert run.trigger_message == "do the thing"
      assert run.run_type == "edit"

      events = PageConversations.list_events(run.id)
      user_msg = Enum.find(events, &(&1.event_type == "user_message"))
      assert user_msg.content == "do the thing"
      assert user_msg.sequence == 0

      # :run_started broadcasted on page topic
      assert_receive {:run_started, %{run_id: _, run_type: "edit", page_id: _}}, 500

      # Session eventually marks run as failed (no real LLM) — just wait for it.
      :ok = wait_for_status(run.id, "failed", 2_000)
    end

    test "reuses existing active conversation on subsequent job", %{args: args, page: page} do
      assert :ok = perform_job(KickoffWorker, args)
      first = PageConversations.get_active_conversation(page.id)

      assert :ok = perform_job(KickoffWorker, Map.put(args, "trigger_message", "second"))
      second = PageConversations.get_active_conversation(page.id)

      assert first.id == second.id
      [run_a, run_b] = PageConversations.list_runs(second.id)

      # Let both background sessions drain to "failed" before the test ends
      # so the sandbox doesn't tear down while they're still writing.
      :ok = wait_for_status(run_a.id, "failed", 2_000)
      :ok = wait_for_status(run_b.id, "failed", 2_000)
    end
  end

  describe "Oban.Worker config" do
    test "queue is :page_agent, max_attempts 1, unique by page_id 30s" do
      spec = KickoffWorker.__opts__()
      assert Keyword.get(spec, :queue) == :page_agent
      assert Keyword.get(spec, :max_attempts) == 1
      unique = Keyword.get(spec, :unique)
      assert unique[:keys] == [:page_id]
      assert unique[:period] == 30
    end
  end

  defp wait_for_status(run_id, target, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_until_status(run_id, target, deadline)
  end

  defp poll_until_status(run_id, target, deadline) do
    case PageConversations.get_run(run_id) do
      %{status: ^target} ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) > deadline do
          :timeout
        else
          Process.sleep(25)
          poll_until_status(run_id, target, deadline)
        end
    end
  end
end
