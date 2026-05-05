defmodule Blackboex.ProjectConversations.ProjectEventTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.ProjectConversations.ProjectConversation
  alias Blackboex.ProjectConversations.ProjectEvent
  alias Blackboex.ProjectConversations.ProjectRun

  setup do
    {user, org} = user_and_org_fixture()
    project = project_fixture(%{user: user, org: org})

    {:ok, conversation} =
      %ProjectConversation{}
      |> ProjectConversation.changeset(%{
        project_id: project.id,
        organization_id: org.id,
        status: "active"
      })
      |> Repo.insert()

    {:ok, run} =
      %ProjectRun{}
      |> ProjectRun.changeset(%{
        conversation_id: conversation.id,
        project_id: project.id,
        organization_id: org.id,
        user_id: user.id,
        run_type: "plan",
        status: "pending",
        trigger_message: "x"
      })
      |> Repo.insert()

    %{run: run}
  end

  describe "valid_event_types/0" do
    test "returns expected list" do
      assert ProjectEvent.valid_event_types() ==
               ~w(user_message assistant_message plan_drafted plan_approved task_dispatched task_completed task_failed completed failed)
    end
  end

  describe "changeset/2" do
    test "valid with required fields", %{run: run} do
      attrs = %{run_id: run.id, sequence: 0, event_type: "user_message", content: "hi"}
      changeset = ProjectEvent.changeset(%ProjectEvent{}, attrs)
      assert changeset.valid?
    end

    test "rejects unknown event_type", %{run: run} do
      attrs = %{run_id: run.id, sequence: 0, event_type: "bogus"}
      changeset = ProjectEvent.changeset(%ProjectEvent{}, attrs)
      refute changeset.valid?
      assert %{event_type: [_]} = errors_on(changeset)
    end

    test "missing required fields produces errors" do
      changeset = ProjectEvent.changeset(%ProjectEvent{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert Map.has_key?(errors, :run_id)
      assert Map.has_key?(errors, :sequence)
      assert Map.has_key?(errors, :event_type)
    end

    test "metadata defaults to empty map and accepts arbitrary JSON", %{run: run} do
      attrs = %{
        run_id: run.id,
        sequence: 0,
        event_type: "completed",
        metadata: %{"input_tokens" => 10, "cost_cents" => 1}
      }

      changeset = ProjectEvent.changeset(%ProjectEvent{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :metadata) == %{"input_tokens" => 10, "cost_cents" => 1}
    end

    test "unique [run_id, sequence] constraint", %{run: run} do
      attrs = %{run_id: run.id, sequence: 0, event_type: "user_message", content: "first"}

      assert {:ok, _} =
               %ProjectEvent{}
               |> ProjectEvent.changeset(attrs)
               |> Repo.insert()

      assert {:error, changeset} =
               %ProjectEvent{}
               |> ProjectEvent.changeset(%{attrs | content: "duplicate"})
               |> Repo.insert()

      refute changeset.valid?
      assert %{run_id: [_]} = Map.take(errors_on(changeset), [:run_id])
    end
  end

  describe "fixture sanity" do
    test "project_event_fixture inserts a row", %{run: run} do
      event = project_event_fixture(%{run: run})
      assert event.id
      assert event.run_id == run.id
    end
  end
end
