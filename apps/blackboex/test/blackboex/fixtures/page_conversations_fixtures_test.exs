defmodule Blackboex.PageConversationsFixturesTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.PageConversations.PageConversation
  alias Blackboex.PageConversations.PageEvent
  alias Blackboex.PageConversations.PageRun

  describe "page_conversation_fixture/1" do
    test "creates an active conversation with valid defaults" do
      conv = page_conversation_fixture()

      assert %PageConversation{} = conv
      assert conv.status == "active"
      assert conv.page_id
      assert conv.organization_id
      assert conv.project_id
    end

    test "accepts an explicit page" do
      {user, org} = user_and_org_fixture()
      page = page_fixture(%{user: user, org: org})

      conv = page_conversation_fixture(%{page: page})

      assert conv.page_id == page.id
      assert conv.organization_id == page.organization_id
      assert conv.project_id == page.project_id
    end

    test "is idempotent for the same page (returns existing active)" do
      {user, org} = user_and_org_fixture()
      page = page_fixture(%{user: user, org: org})

      first = page_conversation_fixture(%{page: page})
      second = page_conversation_fixture(%{page: page})

      assert first.id == second.id
    end
  end

  describe "page_run_fixture/1" do
    test "creates a pending edit run by default" do
      run = page_run_fixture()

      assert %PageRun{} = run
      assert run.run_type == "edit"
      assert run.status == "pending"
      assert run.conversation_id
    end

    test "accepts run_type and trigger_message overrides" do
      run = page_run_fixture(%{run_type: "generate", trigger_message: "write something"})

      assert run.run_type == "generate"
      assert run.trigger_message == "write something"
    end
  end

  describe "page_event_fixture/1" do
    test "creates a user_message event with sequence 0 as the first" do
      run = page_run_fixture()
      event = page_event_fixture(%{run: run})

      assert %PageEvent{} = event
      assert event.event_type == "user_message"
      assert event.sequence == 0
      assert event.run_id == run.id
    end

    test "auto-increments sequence for subsequent events" do
      run = page_run_fixture()
      first = page_event_fixture(%{run: run})
      second = page_event_fixture(%{run: run, event_type: "assistant_message", content: "ok"})

      assert second.sequence == first.sequence + 1
    end
  end
end
