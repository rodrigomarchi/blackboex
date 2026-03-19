defmodule Blackboex.Apis.ApiConversationTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis
  alias Blackboex.Apis.ApiConversation

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

  describe "changeset/2" do
    test "valid changeset with api_id and empty messages", %{api: api} do
      changeset =
        ApiConversation.changeset(%ApiConversation{}, %{
          api_id: api.id,
          messages: []
        })

      assert changeset.valid?
    end

    test "requires api_id" do
      changeset = ApiConversation.changeset(%ApiConversation{}, %{messages: []})
      refute changeset.valid?
      assert %{api_id: [_]} = errors_on(changeset)
    end

    test "messages defaults to empty array", %{api: api} do
      changeset = ApiConversation.changeset(%ApiConversation{}, %{api_id: api.id})
      assert changeset.valid?
    end

    test "messages is array of maps", %{api: api} do
      messages = [
        %{
          "role" => "user",
          "content" => "Add validation",
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      ]

      changeset =
        ApiConversation.changeset(%ApiConversation{}, %{
          api_id: api.id,
          messages: messages
        })

      assert changeset.valid?
    end

    test "metadata defaults to empty map", %{api: api} do
      changeset = ApiConversation.changeset(%ApiConversation{}, %{api_id: api.id})
      assert changeset.valid?

      {:ok, conv} =
        %ApiConversation{}
        |> ApiConversation.changeset(%{api_id: api.id})
        |> Blackboex.Repo.insert()

      assert conv.metadata == %{}
    end

    test "rejects messages with invalid roles", %{api: api} do
      messages = [
        %{"role" => "hacker", "content" => "Bad", "timestamp" => "2026-01-01T00:00:00Z"}
      ]

      changeset =
        ApiConversation.changeset(%ApiConversation{}, %{
          api_id: api.id,
          messages: messages
        })

      refute changeset.valid?
      assert %{messages: [_]} = errors_on(changeset)
    end

    test "rejects messages exceeding max limit", %{api: api} do
      max = ApiConversation.max_messages()

      messages =
        for i <- 1..(max + 1) do
          %{"role" => "user", "content" => "Msg #{i}", "timestamp" => "2026-01-01T00:00:00Z"}
        end

      changeset =
        ApiConversation.changeset(%ApiConversation{}, %{
          api_id: api.id,
          messages: messages
        })

      refute changeset.valid?
      assert %{messages: [_]} = errors_on(changeset)
    end

    test "enforces unique api_id", %{api: api} do
      {:ok, _} =
        %ApiConversation{}
        |> ApiConversation.changeset(%{api_id: api.id})
        |> Blackboex.Repo.insert()

      {:error, changeset} =
        %ApiConversation{}
        |> ApiConversation.changeset(%{api_id: api.id})
        |> Blackboex.Repo.insert()

      assert %{api_id: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
