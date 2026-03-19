defmodule Blackboex.Apis.ConversationsTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis
  alias Blackboex.Apis.ApiConversation
  alias Blackboex.Apis.Conversations

  import Blackboex.AccountsFixtures

  setup do
    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Test API",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(params), do: params"
      })

    %{api: api, user: user, org: org}
  end

  describe "get_or_create_conversation/1" do
    test "creates conversation if none exists", %{api: api} do
      assert {:ok, %ApiConversation{} = conv} = Conversations.get_or_create_conversation(api.id)
      assert conv.api_id == api.id
      assert conv.messages == []
      assert conv.metadata == %{}
    end

    test "returns existing conversation if already exists", %{api: api} do
      {:ok, conv1} = Conversations.get_or_create_conversation(api.id)
      {:ok, conv2} = Conversations.get_or_create_conversation(api.id)
      assert conv1.id == conv2.id
    end
  end

  describe "append_message/3" do
    test "adds message to conversation", %{api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)

      {:ok, updated} = Conversations.append_message(conv, "user", "Add validation")

      assert length(updated.messages) == 1
      [msg] = updated.messages
      assert msg["role"] == "user"
      assert msg["content"] == "Add validation"
      assert msg["timestamp"]
    end

    test "appends to existing messages", %{api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)
      {:ok, conv} = Conversations.append_message(conv, "user", "Add validation")
      {:ok, conv} = Conversations.append_message(conv, "assistant", "Here is the updated code")

      assert length(conv.messages) == 2
      assert Enum.at(conv.messages, 0)["role"] == "user"
      assert Enum.at(conv.messages, 1)["role"] == "assistant"
    end

    test "message format has role, content, timestamp, metadata", %{api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)

      {:ok, updated} =
        Conversations.append_message(conv, "user", "Add validation", %{
          "diff_available" => true
        })

      [msg] = updated.messages
      assert msg["role"] == "user"
      assert msg["content"] == "Add validation"
      assert msg["timestamp"]
      assert msg["metadata"] == %{"diff_available" => true}
    end
  end

  describe "clear_conversation/1" do
    test "resets messages to empty array", %{api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)
      {:ok, conv} = Conversations.append_message(conv, "user", "Hello")
      {:ok, conv} = Conversations.append_message(conv, "assistant", "Hi")

      assert length(conv.messages) == 2

      {:ok, cleared} = Conversations.clear_conversation(conv)

      assert cleared.messages == []
      assert cleared.id == conv.id
    end
  end

  describe "role validation" do
    test "rejects invalid role", %{api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)

      assert {:error, :invalid_role} = Conversations.append_message(conv, "admin", "Hello")
      assert {:error, :invalid_role} = Conversations.append_message(conv, "system", "Hello")
      assert {:error, :invalid_role} = Conversations.append_message(conv, "", "Hello")
    end

    test "accepts valid roles", %{api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)

      assert {:ok, _} = Conversations.append_message(conv, "user", "Hello")
      assert {:ok, _} = Conversations.append_message(conv, "assistant", "Hi")
    end
  end

  describe "concurrent safety" do
    test "concurrent appends do not lose messages", %{api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)

      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            Conversations.append_message(conv, "user", "Message #{i}")
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Reload and verify all 5 messages are present
      {:ok, reloaded} = Conversations.get_or_create_conversation(api.id)
      assert length(reloaded.messages) == 5
    end
  end

  describe "persistence" do
    test "conversation persists and messages accumulate across fetches", %{api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)
      {:ok, _conv} = Conversations.append_message(conv, "user", "First message")

      # Fetch again from DB
      {:ok, reloaded} = Conversations.get_or_create_conversation(api.id)
      assert length(reloaded.messages) == 1
      assert hd(reloaded.messages)["content"] == "First message"

      {:ok, _conv} = Conversations.append_message(reloaded, "assistant", "Response")

      # Fetch again
      {:ok, final} = Conversations.get_or_create_conversation(api.id)
      assert length(final.messages) == 2
    end
  end

  describe "api deletion cascade" do
    test "deleting API removes conversation", %{api: api} do
      {:ok, conv} = Conversations.get_or_create_conversation(api.id)
      {:ok, _conv} = Conversations.append_message(conv, "user", "Hello")

      # Delete the API
      Blackboex.Repo.delete!(api)

      # Conversation should be gone
      assert Blackboex.Repo.get_by(ApiConversation, api_id: api.id) == nil
    end
  end
end
