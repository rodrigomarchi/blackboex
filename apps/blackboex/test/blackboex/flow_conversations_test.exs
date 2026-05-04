defmodule Blackboex.FlowConversationsTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowConversations
  alias Blackboex.FlowConversations.FlowConversation
  alias Blackboex.FlowConversations.FlowEvent
  alias Blackboex.FlowConversations.FlowRun
  alias Ecto.Adapters.SQL.Sandbox

  setup [:create_user_and_org]

  describe "get_or_create_active_conversation/3" do
    test "creates a new conversation when none exists", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})

      assert {:ok, %FlowConversation{} = conv} =
               FlowConversations.get_or_create_active_conversation(
                 flow.id,
                 flow.organization_id,
                 flow.project_id
               )

      assert conv.flow_id == flow.id
      assert conv.organization_id == flow.organization_id
      assert conv.project_id == flow.project_id
      assert conv.status == "active"
      assert conv.total_runs == 0
    end

    test "TOCTOU: concurrent inserts converge to a single active conversation",
         %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})

      # Simulate two workers racing to create the conversation. Using a task
      # supervisor that shares the DB sandbox connection so both tasks see the
      # same tx state.
      parent = self()

      tasks =
        for _ <- 1..4 do
          Task.async(fn ->
            Sandbox.allow(Blackboex.Repo, parent, self())

            FlowConversations.get_or_create_active_conversation(
              flow.id,
              flow.organization_id,
              flow.project_id
            )
          end)
        end

      results = Task.await_many(tasks, 2_000)

      # All calls must return {:ok, _} — the loser of the race fetches the
      # winner instead of propagating the unique-constraint changeset error.
      assert Enum.all?(results, &match?({:ok, _}, &1)),
             "some calls returned error: #{inspect(results)}"

      ids = for {:ok, conv} <- results, do: conv.id

      assert MapSet.size(MapSet.new(ids)) == 1,
             "expected one conversation id, got #{inspect(ids)}"
    end

    test "is idempotent — returns existing conversation on second call",
         %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})

      {:ok, first} =
        FlowConversations.get_or_create_active_conversation(
          flow.id,
          flow.organization_id,
          flow.project_id
        )

      {:ok, second} =
        FlowConversations.get_or_create_active_conversation(
          flow.id,
          flow.organization_id,
          flow.project_id
        )

      assert first.id == second.id
    end
  end

  describe "create_run/1" do
    setup [:setup_conversation]

    test "creates a run with valid attrs and stores definition_before as map",
         %{conversation: conv, user: user} do
      definition = %{"version" => "1.0", "nodes" => [], "edges" => []}

      assert {:ok, %FlowRun{} = run} =
               FlowConversations.create_run(%{
                 conversation_id: conv.id,
                 flow_id: conv.flow_id,
                 organization_id: conv.organization_id,
                 user_id: user.id,
                 run_type: "edit",
                 trigger_message: "adicione um delay",
                 definition_before: definition
               })

      assert run.status == "pending"
      assert run.run_type == "edit"
      assert run.definition_before == definition
    end

    test "rejects invalid run_type", %{conversation: conv, user: user} do
      assert {:error, changeset} =
               FlowConversations.create_run(%{
                 conversation_id: conv.id,
                 flow_id: conv.flow_id,
                 organization_id: conv.organization_id,
                 user_id: user.id,
                 run_type: "refactor",
                 trigger_message: "x"
               })

      assert %{run_type: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects invalid status", %{conversation: conv, user: user} do
      assert {:error, changeset} =
               FlowConversations.create_run(%{
                 conversation_id: conv.id,
                 flow_id: conv.flow_id,
                 organization_id: conv.organization_id,
                 user_id: user.id,
                 run_type: "generate",
                 status: "frozen",
                 trigger_message: "x"
               })

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects trigger_message longer than 10_000 chars",
         %{conversation: conv, user: user} do
      huge = String.duplicate("a", 10_001)

      assert {:error, changeset} =
               FlowConversations.create_run(%{
                 conversation_id: conv.id,
                 flow_id: conv.flow_id,
                 organization_id: conv.organization_id,
                 user_id: user.id,
                 run_type: "generate",
                 trigger_message: huge
               })

      assert %{trigger_message: [msg]} = errors_on(changeset)
      assert msg =~ "should be at most"
    end
  end

  describe "mark_run_running/1" do
    setup [:setup_conversation]

    test "transitions status to running and sets started_at",
         %{user: user, conversation: conv} do
      run = flow_run_fixture(%{conversation: conv, user: user})

      assert {:ok, updated} = FlowConversations.mark_run_running(run)
      assert updated.status == "running"
      assert %DateTime{} = updated.started_at
    end
  end

  describe "complete_run/2" do
    setup [:setup_conversation]

    test "updates status, definition_after, tokens, and duration",
         %{user: user, conversation: conv} do
      run = flow_run_fixture(%{conversation: conv, user: user})
      {:ok, run} = FlowConversations.mark_run_running(run)

      new_def = %{
        "version" => "1.0",
        "nodes" => [%{"id" => "n1", "type" => "start"}],
        "edges" => []
      }

      assert {:ok, completed} =
               FlowConversations.complete_run(run, %{
                 definition_after: new_def,
                 run_summary: "Added start node",
                 input_tokens: 120,
                 output_tokens: 45,
                 cost_cents: 3
               })

      assert completed.status == "completed"
      assert completed.definition_after == new_def
      assert completed.run_summary == "Added start node"
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
      run = flow_run_fixture(%{conversation: conv, user: user})
      {:ok, run} = FlowConversations.mark_run_running(run)

      assert {:ok, failed} = FlowConversations.fail_run(run, "boom")
      assert failed.status == "failed"
      assert failed.error_message == "boom"
      assert %DateTime{} = failed.completed_at
    end
  end

  describe "append_event/2" do
    setup [:setup_conversation]

    test "auto-increments sequence starting at 0",
         %{user: user, conversation: conv} do
      run = flow_run_fixture(%{conversation: conv, user: user})

      assert {:ok, %FlowEvent{sequence: 0}} =
               FlowConversations.append_event(run, %{
                 event_type: "user_message",
                 content: "first"
               })

      assert {:ok, %FlowEvent{sequence: 1}} =
               FlowConversations.append_event(run, %{
                 event_type: "assistant_message",
                 content: "response"
               })
    end

    test "unique constraint prevents duplicate (run_id, sequence)",
         %{user: user, conversation: conv} do
      run = flow_run_fixture(%{conversation: conv, user: user})

      assert {:ok, _} =
               FlowConversations.append_event(run, %{
                 sequence: 0,
                 event_type: "user_message",
                 content: "primeiro"
               })

      assert {:error, changeset} =
               FlowConversations.append_event(run, %{
                 sequence: 0,
                 event_type: "assistant_message",
                 content: "dup"
               })

      assert %{run_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "rejects invalid event_type", %{user: user, conversation: conv} do
      run = flow_run_fixture(%{conversation: conv, user: user})

      assert {:error, changeset} =
               FlowConversations.append_event(run, %{
                 event_type: "nonsense",
                 content: "x"
               })

      assert %{event_type: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts definition_delta event_type", %{user: user, conversation: conv} do
      run = flow_run_fixture(%{conversation: conv, user: user})

      assert {:ok, %FlowEvent{event_type: "definition_delta"}} =
               FlowConversations.append_event(run, %{
                 event_type: "definition_delta",
                 content: "{\"nodes\":["
               })
    end
  end

  describe "list_runs/2" do
    setup [:setup_conversation]

    test "returns all runs from the conversation up to limit",
         %{user: user, conversation: conv} do
      r1 = flow_run_fixture(%{conversation: conv, user: user, trigger_message: "um"})
      r2 = flow_run_fixture(%{conversation: conv, user: user, trigger_message: "dois"})

      ids = conv.id |> FlowConversations.list_runs() |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([r1.id, r2.id])
    end

    test "respects the :limit option", %{user: user, conversation: conv} do
      _ = flow_run_fixture(%{conversation: conv, user: user})
      _ = flow_run_fixture(%{conversation: conv, user: user})

      assert length(FlowConversations.list_runs(conv.id, limit: 1)) == 1
    end
  end

  describe "list_events/2" do
    setup [:setup_conversation]

    test "returns events in ascending sequence order", %{user: user, conversation: conv} do
      run = flow_run_fixture(%{conversation: conv, user: user})

      {:ok, _} =
        FlowConversations.append_event(run, %{event_type: "user_message", content: "a"})

      {:ok, _} =
        FlowConversations.append_event(run, %{event_type: "assistant_message", content: "b"})

      assert [%{sequence: 0}, %{sequence: 1}] = FlowConversations.list_events(run.id)
    end
  end

  describe "start_new_conversation/3 (threads)" do
    test "archives the current active conversation and creates a fresh one",
         %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})

      {:ok, first} =
        FlowConversations.get_or_create_active_conversation(flow.id, org.id, flow.project_id)

      assert first.status == "active"

      {:ok, second} =
        FlowConversations.start_new_conversation(flow.id, org.id, flow.project_id)

      assert second.status == "active"
      assert second.id != first.id

      reloaded_first = FlowConversations.get_conversation(first.id)
      assert reloaded_first.status == "archived"
      assert %DateTime{} = reloaded_first.archived_at
    end

    test "allows multiple archived conversations to coexist with one active",
         %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})

      {:ok, c1} =
        FlowConversations.get_or_create_active_conversation(flow.id, org.id, flow.project_id)

      {:ok, c2} =
        FlowConversations.start_new_conversation(flow.id, org.id, flow.project_id)

      {:ok, c3} =
        FlowConversations.start_new_conversation(flow.id, org.id, flow.project_id)

      assert FlowConversations.get_conversation(c1.id).status == "archived"
      assert FlowConversations.get_conversation(c2.id).status == "archived"
      assert FlowConversations.get_conversation(c3.id).status == "active"
      assert FlowConversations.get_active_conversation(flow.id).id == c3.id
    end
  end

  describe "list_active_conversation_events/2 and thread_history/2" do
    test "only returns events from the active conversation", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})

      conv1 = flow_conversation_fixture(%{flow: flow})
      run1 = flow_run_fixture(%{conversation: conv1, user: user})

      {:ok, _} =
        FlowConversations.append_event(run1, %{
          event_type: "user_message",
          content: "msg arquivada"
        })

      {:ok, _} = FlowConversations.archive_active_conversation(flow.id)

      {:ok, conv2} =
        FlowConversations.get_or_create_active_conversation(flow.id, org.id, flow.project_id)

      run2 = flow_run_fixture(%{conversation: conv2, user: user})

      {:ok, _} =
        FlowConversations.append_event(run2, %{
          event_type: "user_message",
          content: "msg viva"
        })

      {:ok, _} =
        FlowConversations.append_event(run2, %{
          event_type: "completed",
          content: "ok, pronto"
        })

      events = FlowConversations.list_active_conversation_events(flow.id)
      contents = Enum.map(events, & &1.content)
      assert "msg viva" in contents
      assert "ok, pronto" in contents
      refute "msg arquivada" in contents
    end

    test "thread_history returns user/assistant pairs in order, skipping archived",
         %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      conv = flow_conversation_fixture(%{flow: flow})
      run = flow_run_fixture(%{conversation: conv, user: user})

      {:ok, _} =
        FlowConversations.append_event(run, %{event_type: "user_message", content: "hi"})

      {:ok, _} =
        FlowConversations.append_event(run, %{event_type: "completed", content: "hello"})

      assert [
               %{role: "user", content: "hi"},
               %{role: "assistant", content: "hello"}
             ] = FlowConversations.thread_history(flow.id)
    end

    test "thread_history returns [] when no active conversation",
         %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      assert [] == FlowConversations.thread_history(flow.id)
    end
  end

  describe "increment_conversation_stats/2" do
    setup [:setup_conversation]

    test "atomically increments counters", %{conversation: conv} do
      FlowConversations.increment_conversation_stats(conv,
        total_runs: 1,
        total_events: 3,
        total_input_tokens: 100,
        total_cost_cents: 2
      )

      reloaded = FlowConversations.get_conversation(conv.id)
      assert reloaded.total_runs == 1
      assert reloaded.total_events == 3
      assert reloaded.total_input_tokens == 100
      assert reloaded.total_cost_cents == 2
    end
  end

  describe "fixture helpers" do
    test "flow_conversation_fixture creates active conversation with defaults",
         %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      conv = flow_conversation_fixture(%{flow: flow})

      assert %FlowConversation{status: "active"} = conv
      assert conv.flow_id == flow.id
    end

    test "flow_run_fixture defaults to :run_type 'edit' and empty definition_before",
         %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      conv = flow_conversation_fixture(%{flow: flow})
      run = flow_run_fixture(%{conversation: conv, user: user})

      assert run.run_type == "edit"
      assert run.definition_before == %{}
      assert run.status == "pending"
    end

    test "flow_event_fixture auto-increments sequence within the same run",
         %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      conv = flow_conversation_fixture(%{flow: flow})
      run = flow_run_fixture(%{conversation: conv, user: user})

      e1 = flow_event_fixture(%{run: run})
      e2 = flow_event_fixture(%{run: run})

      assert e1.sequence == 0
      assert e2.sequence == 1
    end
  end

  # ── helpers ───────────────────────────────────────────────

  defp setup_conversation(%{user: user, org: org} = context) do
    flow = flow_fixture(%{user: user, org: org})
    conv = flow_conversation_fixture(%{flow: flow})
    Map.merge(context, %{flow: flow, conversation: conv})
  end
end
