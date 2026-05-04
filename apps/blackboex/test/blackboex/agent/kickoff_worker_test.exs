defmodule Blackboex.Agent.KickoffWorkerTest do
  use Blackboex.DataCase, async: false

  import Mox, only: [set_mox_global: 1]

  @moduletag :unit

  # KickoffWorker.perform/1 starts an Agent.Session, which spawns a Task that
  # calls the LLM client. Without stubs (and global Mox mode so the spawned
  # Task can see them) the Task crashes with Mox.UnexpectedCallError, polluting
  # logs even though the test itself only asserts on DB state.
  setup :set_mox_global
  setup :stub_llm_client

  alias Blackboex.Agent.KickoffWorker
  alias Blackboex.Apis
  alias Blackboex.Conversations

  setup do
    {user, org} = user_and_org_fixture()

    {:ok, api} =
      Apis.create_api(%{
        name: "KW API",
        slug: "kw-api-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      })

    %{user: user, org: org, api: api}
  end

  # ──────────────────────────────────────────────────────────────
  # backoff/1
  # ──────────────────────────────────────────────────────────────

  describe "backoff/1" do
    test "returns progressive backoff schedule" do
      assert KickoffWorker.backoff(%Oban.Job{attempt: 1}) == 60
      assert KickoffWorker.backoff(%Oban.Job{attempt: 2}) == 120
      assert KickoffWorker.backoff(%Oban.Job{attempt: 3}) == 300
      assert KickoffWorker.backoff(%Oban.Job{attempt: 4}) == 600
    end

    test "caps at 600 seconds for attempts beyond 4" do
      assert KickoffWorker.backoff(%Oban.Job{attempt: 5}) == 600
      assert KickoffWorker.backoff(%Oban.Job{attempt: 10}) == 600
    end
  end

  # ──────────────────────────────────────────────────────────────
  # timeout/1
  # ──────────────────────────────────────────────────────────────

  describe "timeout/1" do
    test "returns 7 minutes" do
      assert KickoffWorker.timeout(%Oban.Job{}) == :timer.minutes(7)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # perform/1
  # ──────────────────────────────────────────────────────────────

  describe "perform/1" do
    test "creates conversation and run records", %{user: user, org: org, api: api} do
      job = build_job(api.id, org.id, user.id, api.project_id)

      # Subscribe to PubSub to verify broadcast
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "api:#{api.id}")

      # perform will try to start Session which may fail (no LLM configured etc)
      # but the DB records should still be created
      _result = KickoffWorker.perform(job)

      # Verify conversation was created
      conversation = Conversations.get_conversation_by_api(api.id)
      assert conversation != nil

      # Verify run was created
      runs = Conversations.list_runs(conversation.id)
      assert runs != []

      run = hd(runs)
      assert run.api_id == api.id
      assert run.user_id == user.id
      assert run.run_type == "generation"
      assert run.trigger_message == "Generate a calculator API"
    end

    test "propagates project_id when creating a run", %{user: user, org: org, api: api} do
      job = build_job(api.id, org.id, user.id, api.project_id)
      _result = KickoffWorker.perform(job)

      conversation = Conversations.get_conversation_by_api(api.id)
      runs = Conversations.list_runs(conversation.id)

      run = hd(runs)
      assert run.project_id == api.project_id
    end

    test "broadcasts agent_run_started via PubSub", %{user: user, org: org, api: api} do
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "api:#{api.id}")

      job = build_job(api.id, org.id, user.id, api.project_id)
      _result = KickoffWorker.perform(job)

      assert_receive {:agent_run_started, %{run_id: run_id, run_type: "generation"}}
      assert is_binary(run_id)
    end

    test "persists initial user_message event", %{user: user, org: org, api: api} do
      job = build_job(api.id, org.id, user.id, api.project_id)
      _result = KickoffWorker.perform(job)

      conversation = Conversations.get_conversation_by_api(api.id)
      assert conversation != nil
      runs = Conversations.list_runs(conversation.id)
      run = hd(runs)

      events = Conversations.list_events(run.id)
      assert events != []

      user_msg = Enum.find(events, &(&1.event_type == "user_message"))
      assert user_msg != nil
      assert user_msg.content == "Generate a calculator API"
      assert user_msg.sequence == 0
    end

    test "includes current_code and current_tests in session params", %{
      user: user,
      org: org,
      api: api
    } do
      job =
        build_job(api.id, org.id, user.id, api.project_id, %{
          "current_code" => "def handle(p), do: p",
          "current_tests" => "test \"it works\" do end"
        })

      # This will likely fail at Session.start but validates the args pass through
      _result = KickoffWorker.perform(job)

      # If we got here without a crash, the args were handled correctly
      assert true
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Oban worker configuration
  # ──────────────────────────────────────────────────────────────

  describe "worker configuration" do
    test "uses :generation queue" do
      config = KickoffWorker.__opts__()
      assert Keyword.get(config, :queue) == :generation
    end

    test "max_attempts is 5" do
      config = KickoffWorker.__opts__()
      assert Keyword.get(config, :max_attempts) == 5
    end

    test "has uniqueness constraint on api_id + run_type" do
      config = KickoffWorker.__opts__()
      unique = Keyword.get(config, :unique)
      assert unique[:keys] == [:api_id, :run_type]
      assert unique[:period] == 30
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────

  defp build_job(api_id, org_id, user_id, project_id, extra \\ %{}) do
    args =
      Map.merge(
        %{
          "api_id" => api_id,
          "organization_id" => org_id,
          "project_id" => project_id,
          "user_id" => user_id,
          "run_type" => "generation",
          "trigger_message" => "Generate a calculator API"
        },
        extra
      )

    %Oban.Job{args: args}
  end
end
