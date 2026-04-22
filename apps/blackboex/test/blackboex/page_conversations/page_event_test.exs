defmodule Blackboex.PageConversations.PageEventTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.PageConversations.PageConversation
  alias Blackboex.PageConversations.PageEvent
  alias Blackboex.PageConversations.PageRun

  setup do
    {user, org} = user_and_org_fixture()
    page = page_fixture(%{user: user, org: org})

    {:ok, conversation} =
      %PageConversation{}
      |> PageConversation.changeset(%{
        page_id: page.id,
        organization_id: org.id,
        project_id: page.project_id,
        status: "active"
      })
      |> Repo.insert()

    {:ok, run} =
      %PageRun{}
      |> PageRun.changeset(%{
        conversation_id: conversation.id,
        page_id: page.id,
        organization_id: org.id,
        user_id: user.id,
        run_type: "edit",
        status: "pending",
        trigger_message: "edit"
      })
      |> Repo.insert()

    %{run: run}
  end

  describe "valid_event_types/0" do
    test "returns expected list" do
      assert PageEvent.valid_event_types() ==
               ~w(user_message assistant_message content_delta completed failed)
    end
  end

  describe "changeset/2" do
    test "valid with required fields", %{run: run} do
      attrs = %{run_id: run.id, sequence: 0, event_type: "user_message", content: "hi"}
      changeset = PageEvent.changeset(%PageEvent{}, attrs)
      assert changeset.valid?
    end

    test "rejects unknown event_type", %{run: run} do
      attrs = %{run_id: run.id, sequence: 0, event_type: "bogus"}
      changeset = PageEvent.changeset(%PageEvent{}, attrs)
      refute changeset.valid?
      assert %{event_type: [_]} = errors_on(changeset)
    end

    test "missing required fields produces errors" do
      changeset = PageEvent.changeset(%PageEvent{}, %{})
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

      changeset = PageEvent.changeset(%PageEvent{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :metadata) == %{"input_tokens" => 10, "cost_cents" => 1}
    end

    test "unique [run_id, sequence] constraint", %{run: run} do
      attrs = %{run_id: run.id, sequence: 0, event_type: "user_message", content: "first"}

      assert {:ok, _} =
               %PageEvent{}
               |> PageEvent.changeset(attrs)
               |> Repo.insert()

      assert {:error, changeset} =
               %PageEvent{}
               |> PageEvent.changeset(%{attrs | content: "duplicate"})
               |> Repo.insert()

      refute changeset.valid?
      assert %{run_id: [_]} = errors_on(changeset) |> Map.take([:run_id, :sequence])
    end
  end
end
