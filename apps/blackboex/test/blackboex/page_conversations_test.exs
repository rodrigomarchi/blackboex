defmodule Blackboex.PageConversationsTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.PageConversations
  alias Blackboex.PageConversations.PageConversation

  setup do
    {user, org} = user_and_org_fixture()
    page = page_fixture(%{user: user, org: org})
    %{user: user, org: org, page: page}
  end

  describe "get_or_create_active_conversation/3" do
    test "creates a new conversation when none exists", %{page: page, org: org} do
      assert {:ok, %PageConversation{} = conv} =
               PageConversations.get_or_create_active_conversation(
                 page.id,
                 org.id,
                 page.project_id
               )

      assert conv.status == "active"
      assert conv.page_id == page.id
    end

    test "returns existing active conversation on second call", %{page: page, org: org} do
      {:ok, first} =
        PageConversations.get_or_create_active_conversation(page.id, org.id, page.project_id)

      {:ok, second} =
        PageConversations.get_or_create_active_conversation(page.id, org.id, page.project_id)

      assert first.id == second.id
    end
  end

  describe "start_new_conversation/3" do
    test "archives current active and creates a fresh active", %{page: page, org: org} do
      {:ok, old} =
        PageConversations.get_or_create_active_conversation(page.id, org.id, page.project_id)

      {:ok, new_conv} =
        PageConversations.start_new_conversation(page.id, org.id, page.project_id)

      old = Repo.reload!(old)
      assert old.status == "archived"
      assert old.archived_at
      assert new_conv.id != old.id
      assert new_conv.status == "active"
    end
  end

  describe "archive_active_conversation/1" do
    test "noop when no active conversation", %{page: page} do
      assert :noop = PageConversations.archive_active_conversation(page.id)
    end

    test "archives the active conversation when present", %{page: page, org: org} do
      {:ok, conv} =
        PageConversations.get_or_create_active_conversation(page.id, org.id, page.project_id)

      {:ok, archived} = PageConversations.archive_active_conversation(page.id)
      assert archived.id == conv.id
      assert archived.status == "archived"
    end
  end

  describe "create_run/1 and lifecycle" do
    setup %{user: user, org: org, page: page} do
      conv = page_conversation_fixture(%{page: page})
      %{conv: conv, user: user, org: org, page: page}
    end

    test "create_run/1 creates a pending run", %{conv: conv, user: user, page: page} do
      assert {:ok, run} =
               PageConversations.create_run(%{
                 conversation_id: conv.id,
                 page_id: page.id,
                 organization_id: conv.organization_id,
                 user_id: user.id,
                 run_type: "edit",
                 status: "pending",
                 trigger_message: "go"
               })

      assert run.status == "pending"
    end

    test "mark_run_running/1 sets status and started_at" do
      run = page_run_fixture()
      assert {:ok, started} = PageConversations.mark_run_running(run)
      assert started.status == "running"
      assert started.started_at
    end

    test "complete_run/2 persists status, content_after, summary, tokens" do
      run = page_run_fixture()
      {:ok, run} = PageConversations.mark_run_running(run)

      assert {:ok, completed} =
               PageConversations.complete_run(run, %{
                 content_after: "# Hi",
                 run_summary: "wrote intro",
                 input_tokens: 100,
                 output_tokens: 200
               })

      assert completed.status == "completed"
      assert completed.content_after == "# Hi"
      assert completed.input_tokens == 100
      assert completed.duration_ms >= 0
    end

    test "fail_run/2 persists error_message and failed status" do
      run = page_run_fixture()
      {:ok, run} = PageConversations.mark_run_running(run)

      assert {:ok, failed} = PageConversations.fail_run(run, "boom")
      assert failed.status == "failed"
      assert failed.error_message == "boom"
    end
  end

  describe "append_event/2 and listing" do
    setup %{page: page} do
      conv = page_conversation_fixture(%{page: page})
      run = page_run_fixture(%{conversation: conv})
      %{run: run, conv: conv}
    end

    test "auto-assigns sequence per run", %{run: run} do
      {:ok, e0} = PageConversations.append_event(run, %{event_type: "user_message", content: "a"})

      {:ok, e1} =
        PageConversations.append_event(run, %{event_type: "assistant_message", content: "b"})

      assert e0.sequence == 0
      assert e1.sequence == 1
    end

    test "list_active_conversation_events/2 returns events from active conversation only",
         %{page: page, org: org, run: run} do
      {:ok, _} = PageConversations.append_event(run, %{event_type: "user_message", content: "a"})

      # Archive and start a new conversation; old events must NOT appear.
      {:ok, _} = PageConversations.archive_active_conversation(run.page_id)
      {:ok, _} = PageConversations.start_new_conversation(page.id, org.id, page.project_id)

      assert PageConversations.list_active_conversation_events(page.id) == []
    end

    test "list_active_conversation_events/2 respects limit", %{page: page, run: run} do
      for i <- 0..4 do
        {:ok, _} =
          PageConversations.append_event(run, %{
            event_type: "user_message",
            content: "msg #{i}"
          })
      end

      events = PageConversations.list_active_conversation_events(page.id, limit: 3)
      assert length(events) == 3
    end
  end

  describe "thread_history/2" do
    setup %{page: page} do
      conv = page_conversation_fixture(%{page: page})
      run = page_run_fixture(%{conversation: conv})
      %{run: run, conv: conv}
    end

    test "returns user/assistant pairs oldest-first", %{run: run, page: page} do
      {:ok, _} = PageConversations.append_event(run, %{event_type: "user_message", content: "q1"})

      {:ok, _} =
        PageConversations.append_event(run, %{event_type: "completed", content: "a1"})

      {:ok, _} = PageConversations.append_event(run, %{event_type: "user_message", content: "q2"})

      history = PageConversations.thread_history(page.id)

      assert history == [
               %{role: "user", content: "q1"},
               %{role: "assistant", content: "a1"},
               %{role: "user", content: "q2"}
             ]
    end

    test "ignores content_delta and failed events", %{run: run, page: page} do
      {:ok, _} = PageConversations.append_event(run, %{event_type: "user_message", content: "q"})

      {:ok, _} =
        PageConversations.append_event(run, %{event_type: "content_delta", content: "partial"})

      {:ok, _} = PageConversations.append_event(run, %{event_type: "failed", content: "err"})

      assert PageConversations.thread_history(page.id) == [
               %{role: "user", content: "q"}
             ]
    end

    test "respects limit and keeps most recent", %{run: run, page: page} do
      for i <- 1..5 do
        {:ok, _} =
          PageConversations.append_event(run, %{
            event_type: "user_message",
            content: "q#{i}"
          })
      end

      history = PageConversations.thread_history(page.id, limit: 2)
      assert length(history) == 2
      assert List.last(history).content == "q5"
    end
  end

  describe "race conditions" do
    test "concurrent get_or_create_active_conversation/3 returns the same active",
         %{page: page, org: org} do
      tasks =
        for _ <- 1..5 do
          Task.async(fn ->
            PageConversations.get_or_create_active_conversation(page.id, org.id, page.project_id)
          end)
        end

      results = Task.await_many(tasks, 5_000)
      ids = for {:ok, %{id: id}} <- results, do: id
      assert length(Enum.uniq(ids)) == 1
    end
  end

  describe "increment_conversation_stats/2" do
    test "increments accumulated counters", %{page: page} do
      conv = page_conversation_fixture(%{page: page})

      PageConversations.increment_conversation_stats(conv,
        total_runs: 1,
        total_input_tokens: 10
      )

      PageConversations.increment_conversation_stats(conv,
        total_runs: 2,
        total_input_tokens: 5
      )

      reloaded = Repo.reload!(conv)
      assert reloaded.total_runs == 3
      assert reloaded.total_input_tokens == 15
    end
  end
end
