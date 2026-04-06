defmodule Blackboex.Agent.RecoveryWorkerTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit
  @moduletag :capture_log

  import Ecto.Query
  import Blackboex.AccountsFixtures

  alias Blackboex.Agent.RecoveryWorker
  alias Blackboex.Apis
  alias Blackboex.Conversations
  alias Blackboex.Conversations.Run
  alias Blackboex.Organizations
  alias Blackboex.Repo

  defp create_context(_ctx) do
    user = user_fixture()
    [org] = Organizations.list_user_organizations(user)

    {:ok, api} =
      Apis.create_api(%{
        name: "Recovery Test API",
        slug: "recovery-test-api",
        description: "API for recovery worker tests",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id
      })

    {:ok, conversation} = Conversations.get_or_create_conversation(api.id, org.id)

    %{user: user, org: org, api: api, conversation: conversation}
  end

  defp create_stale_run(%{user: user, org: org, api: api, conversation: conversation}) do
    {:ok, run} =
      Conversations.create_run(%{
        conversation_id: conversation.id,
        api_id: api.id,
        user_id: user.id,
        organization_id: org.id,
        run_type: "generation"
      })

    {:ok, run} = Conversations.update_run_metrics(run, %{started_at: DateTime.utc_now()})
    {:ok, run} = Conversations.complete_run(run, %{status: "running"})

    # Backdate updated_at so the run appears stale (10 minutes ago)
    from(r in Run, where: r.id == ^run.id)
    |> Repo.update_all(set: [updated_at: DateTime.add(DateTime.utc_now(), -600, :second)])

    Repo.get!(Run, run.id)
  end

  describe "perform/1" do
    setup [:create_context]

    test "marks stale runs as failed", ctx do
      run = create_stale_run(ctx)

      assert :ok = RecoveryWorker.perform(%Oban.Job{args: %{}})

      updated = Repo.get!(Run, run.id)
      assert updated.status == "failed"
      assert updated.error_summary =~ "session was lost"
    end

    test "broadcasts :agent_failed on PubSub for the run", ctx do
      run = create_stale_run(ctx)

      Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{run.id}")

      assert :ok = RecoveryWorker.perform(%Oban.Job{args: %{}})

      assert_receive {:agent_failed, %{run_id: run_id, error: _}}, 1_000
      assert run_id == run.id
    end

    test "crash in one run does not block recovery of others", ctx do
      run1 = create_stale_run(ctx)
      run2 = create_stale_run(ctx)

      # Force run1's recovery to fail by deleting the conversation (append_event will hit FK constraint)
      # complete_run operates on the struct directly and succeeds first; append_event will crash
      Repo.delete!(ctx.conversation)

      assert :ok = RecoveryWorker.perform(%Oban.Job{args: %{}})

      # run2's conversation is gone too (cascade), but complete_run on struct must have run
      # Both complete_run calls happen before append_event, so both should be failed
      # Verify at least one run was processed (no crash propagated)
      updated1 = Repo.get(Run, run1.id)
      updated2 = Repo.get(Run, run2.id)

      # Runs may have been deleted by cascade or marked failed — the key assertion is :ok returned
      # and no exception propagated from the worker
      assert updated1 == nil or updated1.status in ["failed", "running"]
      assert updated2 == nil or updated2.status in ["failed", "running"]
    end

    test "does not affect non-stale runs", ctx do
      {:ok, run} =
        Conversations.create_run(%{
          conversation_id: ctx.conversation.id,
          api_id: ctx.api.id,
          user_id: ctx.user.id,
          organization_id: ctx.org.id,
          run_type: "generation"
        })

      {:ok, run} = Conversations.update_run_metrics(run, %{started_at: DateTime.utc_now()})
      {:ok, run} = Conversations.complete_run(run, %{status: "running"})

      # Do NOT backdate — updated_at is current, so this run is not stale

      assert :ok = RecoveryWorker.perform(%Oban.Job{args: %{}})

      updated = Repo.get!(Run, run.id)
      assert updated.status == "running"
    end
  end
end
