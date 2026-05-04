defmodule Blackboex.PlaygroundConversationsTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.PlaygroundConversations
  alias Blackboex.PlaygroundConversations.PlaygroundConversation
  alias Blackboex.PlaygroundConversations.PlaygroundEvent
  alias Blackboex.PlaygroundConversations.PlaygroundRun

  setup [:create_user_and_org]

  describe "get_or_create_active_conversation/3" do
    test "creates a new conversation when none exists", %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})

      assert {:ok, %PlaygroundConversation{} = conv} =
               PlaygroundConversations.get_or_create_active_conversation(
                 pg.id,
                 pg.organization_id,
                 pg.project_id
               )

      assert conv.playground_id == pg.id
      assert conv.organization_id == pg.organization_id
      assert conv.project_id == pg.project_id
      assert conv.total_runs == 0
    end

    test "is idempotent — returns existing conversation on second call", %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})

      {:ok, first} =
        PlaygroundConversations.get_or_create_active_conversation(
          pg.id,
          pg.organization_id,
          pg.project_id
        )

      {:ok, second} =
        PlaygroundConversations.get_or_create_active_conversation(
          pg.id,
          pg.organization_id,
          pg.project_id
        )

      assert first.id == second.id
    end
  end

  describe "create_run/1" do
    setup [:setup_conversation]

    test "creates a run with valid attrs", %{conversation: conv, user: user} do
      assert {:ok, %PlaygroundRun{} = run} =
               PlaygroundConversations.create_run(%{
                 conversation_id: conv.id,
                 playground_id: conv.playground_id,
                 organization_id: conv.organization_id,
                 user_id: user.id,
                 run_type: "edit",
                 trigger_message: "add a comment",
                 code_before: "IO.puts :ok"
               })

      assert run.status == "pending"
      assert run.run_type == "edit"
      assert run.code_before == "IO.puts :ok"
    end

    test "rejects invalid run_type", %{conversation: conv, user: user} do
      assert {:error, changeset} =
               PlaygroundConversations.create_run(%{
                 conversation_id: conv.id,
                 playground_id: conv.playground_id,
                 organization_id: conv.organization_id,
                 user_id: user.id,
                 run_type: "refactor",
                 trigger_message: "x"
               })

      assert %{run_type: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects invalid status", %{conversation: conv, user: user} do
      assert {:error, changeset} =
               PlaygroundConversations.create_run(%{
                 conversation_id: conv.id,
                 playground_id: conv.playground_id,
                 organization_id: conv.organization_id,
                 user_id: user.id,
                 run_type: "generate",
                 status: "frozen",
                 trigger_message: "x"
               })

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "mark_run_running/1" do
    setup [:setup_conversation]

    test "transitions status to running and sets started_at", %{user: user, conversation: conv} do
      run = playground_run_fixture(%{conversation: conv, user: user})

      assert {:ok, updated} = PlaygroundConversations.mark_run_running(run)
      assert updated.status == "running"
      assert %DateTime{} = updated.started_at
    end
  end

  describe "complete_run/2" do
    setup [:setup_conversation]

    test "updates status, code_after, tokens, and duration",
         %{user: user, conversation: conv} do
      run = playground_run_fixture(%{conversation: conv, user: user})
      {:ok, run} = PlaygroundConversations.mark_run_running(run)

      assert {:ok, completed} =
               PlaygroundConversations.complete_run(run, %{
                 code_after: "IO.puts :done",
                 run_summary: "Added done message",
                 input_tokens: 120,
                 output_tokens: 45,
                 cost_cents: 3
               })

      assert completed.status == "completed"
      assert completed.code_after == "IO.puts :done"
      assert completed.input_tokens == 120
      assert completed.output_tokens == 45
      assert completed.cost_cents == 3
      assert %DateTime{} = completed.completed_at
      assert is_integer(completed.duration_ms)
      assert completed.duration_ms >= 0
    end
  end

  describe "fail_run/2" do
    setup [:setup_conversation]

    test "sets status failed and error_message", %{user: user, conversation: conv} do
      run = playground_run_fixture(%{conversation: conv, user: user})
      {:ok, run} = PlaygroundConversations.mark_run_running(run)

      assert {:ok, failed} = PlaygroundConversations.fail_run(run, "boom")
      assert failed.status == "failed"
      assert failed.error_message == "boom"
      assert %DateTime{} = failed.completed_at
    end
  end

  describe "append_event/2" do
    setup [:setup_conversation]

    test "auto-increments sequence starting at 0", %{user: user, conversation: conv} do
      run = playground_run_fixture(%{conversation: conv, user: user})

      assert {:ok, %PlaygroundEvent{sequence: 0}} =
               PlaygroundConversations.append_event(run, %{
                 event_type: "user_message",
                 content: "first"
               })

      assert {:ok, %PlaygroundEvent{sequence: 1}} =
               PlaygroundConversations.append_event(run, %{
                 event_type: "assistant_message",
                 content: "reply"
               })
    end

    test "unique constraint prevents duplicate (run_id, sequence)",
         %{user: user, conversation: conv} do
      run = playground_run_fixture(%{conversation: conv, user: user})

      assert {:ok, _} =
               PlaygroundConversations.append_event(run, %{
                 sequence: 0,
                 event_type: "user_message",
                 content: "first"
               })

      assert {:error, changeset} =
               PlaygroundConversations.append_event(run, %{
                 sequence: 0,
                 event_type: "assistant_message",
                 content: "dup"
               })

      assert %{run_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "rejects invalid event_type", %{user: user, conversation: conv} do
      run = playground_run_fixture(%{conversation: conv, user: user})

      assert {:error, changeset} =
               PlaygroundConversations.append_event(run, %{
                 event_type: "nonsense",
                 content: "x"
               })

      assert %{event_type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "list_runs/2" do
    setup [:setup_conversation]

    test "returns all runs from the conversation up to limit",
         %{user: user, conversation: conv} do
      r1 = playground_run_fixture(%{conversation: conv, user: user, trigger_message: "one"})
      r2 = playground_run_fixture(%{conversation: conv, user: user, trigger_message: "two"})

      ids = conv.id |> PlaygroundConversations.list_runs() |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([r1.id, r2.id])
    end

    test "respects the :limit option", %{user: user, conversation: conv} do
      _ = playground_run_fixture(%{conversation: conv, user: user})
      _ = playground_run_fixture(%{conversation: conv, user: user})

      assert length(PlaygroundConversations.list_runs(conv.id, limit: 1)) == 1
    end
  end

  describe "list_events/2" do
    setup [:setup_conversation]

    test "returns events in ascending sequence order", %{user: user, conversation: conv} do
      run = playground_run_fixture(%{conversation: conv, user: user})

      {:ok, _} =
        PlaygroundConversations.append_event(run, %{event_type: "user_message", content: "a"})

      {:ok, _} =
        PlaygroundConversations.append_event(run, %{
          event_type: "assistant_message",
          content: "b"
        })

      assert [%{sequence: 0}, %{sequence: 1}] = PlaygroundConversations.list_events(run.id)
    end
  end

  describe "start_new_conversation/3 (threads)" do
    test "archives the current active conversation and creates a fresh one",
         %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})

      {:ok, first} =
        PlaygroundConversations.get_or_create_active_conversation(pg.id, org.id, pg.project_id)

      assert first.status == "active"

      {:ok, second} =
        PlaygroundConversations.start_new_conversation(pg.id, org.id, pg.project_id)

      assert second.status == "active"
      assert second.id != first.id

      reloaded_first = PlaygroundConversations.get_conversation(first.id)
      assert reloaded_first.status == "archived"
      assert %DateTime{} = reloaded_first.archived_at
    end

    test "allows multiple archived conversations to coexist with one active",
         %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})

      {:ok, c1} =
        PlaygroundConversations.get_or_create_active_conversation(pg.id, org.id, pg.project_id)

      {:ok, c2} =
        PlaygroundConversations.start_new_conversation(pg.id, org.id, pg.project_id)

      {:ok, c3} =
        PlaygroundConversations.start_new_conversation(pg.id, org.id, pg.project_id)

      assert PlaygroundConversations.get_conversation(c1.id).status == "archived"
      assert PlaygroundConversations.get_conversation(c2.id).status == "archived"
      assert PlaygroundConversations.get_conversation(c3.id).status == "active"
      assert PlaygroundConversations.get_active_conversation(pg.id).id == c3.id
    end
  end

  describe "list_active_conversation_events/2 and thread_history/2" do
    test "only returns events from the active conversation", %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})

      conv1 = playground_conversation_fixture(%{playground: pg})
      run1 = playground_run_fixture(%{conversation: conv1, user: user})

      {:ok, _} =
        PlaygroundConversations.append_event(run1, %{
          event_type: "user_message",
          content: "msg from archived"
        })

      {:ok, _} = PlaygroundConversations.archive_active_conversation(pg.id)

      {:ok, conv2} =
        PlaygroundConversations.get_or_create_active_conversation(pg.id, org.id, pg.project_id)

      run2 = playground_run_fixture(%{conversation: conv2, user: user})

      {:ok, _} =
        PlaygroundConversations.append_event(run2, %{
          event_type: "user_message",
          content: "live message"
        })

      {:ok, _} =
        PlaygroundConversations.append_event(run2, %{
          event_type: "completed",
          content: "ok, pronto"
        })

      events = PlaygroundConversations.list_active_conversation_events(pg.id)
      contents = Enum.map(events, & &1.content)
      assert "live message" in contents
      assert "ok, pronto" in contents
      refute "msg from archived" in contents
    end

    test "thread_history returns user/assistant pairs in order, skipping archived",
         %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})
      conv = playground_conversation_fixture(%{playground: pg})
      run = playground_run_fixture(%{conversation: conv, user: user})

      {:ok, _} =
        PlaygroundConversations.append_event(run, %{event_type: "user_message", content: "hi"})

      {:ok, _} =
        PlaygroundConversations.append_event(run, %{event_type: "completed", content: "hello"})

      assert [
               %{role: "user", content: "hi"},
               %{role: "assistant", content: "hello"}
             ] = PlaygroundConversations.thread_history(pg.id)
    end
  end

  describe "increment_conversation_stats/2" do
    setup [:setup_conversation]

    test "atomically increments counters", %{conversation: conv} do
      PlaygroundConversations.increment_conversation_stats(conv,
        total_runs: 1,
        total_events: 3,
        total_input_tokens: 100,
        total_cost_cents: 2
      )

      reloaded = PlaygroundConversations.get_conversation(conv.id)
      assert reloaded.total_runs == 1
      assert reloaded.total_events == 3
      assert reloaded.total_input_tokens == 100
      assert reloaded.total_cost_cents == 2
    end
  end

  # ── helpers ───────────────────────────────────────────────

  defp setup_conversation(%{user: user, org: org} = context) do
    pg = playground_fixture(%{user: user, org: org})
    conv = playground_conversation_fixture(%{playground: pg})
    Map.merge(context, %{playground: pg, conversation: conv})
  end
end
