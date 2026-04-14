defmodule Blackboex.Apis.DataStoreTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis
  alias Blackboex.Apis.DataStore

  setup do
    {user, org} = user_and_org_fixture()

    {:ok, api} =
      Apis.create_api(%{
        name: "Test API",
        template_type: "crud",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      })

    %{api: api, org: org, user: user}
  end

  describe "put/3" do
    test "creates new entry", %{api: api} do
      assert {:ok, entry} = DataStore.put(api.id, "key1", %{"name" => "Alice"})
      assert entry.key == "key1"
      assert entry.value == %{"name" => "Alice"}
      assert entry.api_id == api.id
    end

    test "updates existing entry (upsert)", %{api: api} do
      {:ok, _} = DataStore.put(api.id, "key1", %{"name" => "Alice"})
      {:ok, updated} = DataStore.put(api.id, "key1", %{"name" => "Bob"})

      assert updated.value == %{"name" => "Bob"}
      assert updated.key == "key1"
    end
  end

  describe "get/2" do
    test "returns entry", %{api: api} do
      {:ok, _} = DataStore.put(api.id, "key1", %{"name" => "Alice"})

      entry = DataStore.get(api.id, "key1")
      assert entry.value == %{"name" => "Alice"}
    end

    test "returns nil for missing key", %{api: api} do
      assert DataStore.get(api.id, "nonexistent") == nil
    end
  end

  describe "list/1" do
    test "returns all entries for the API", %{api: api} do
      {:ok, _} = DataStore.put(api.id, "b_key", %{"name" => "Bob"})
      {:ok, _} = DataStore.put(api.id, "a_key", %{"name" => "Alice"})

      entries = DataStore.list(api.id)
      assert length(entries) == 2
      assert hd(entries).key == "a_key"
    end
  end

  describe "delete/2" do
    test "removes entry", %{api: api} do
      {:ok, _} = DataStore.put(api.id, "key1", %{"name" => "Alice"})
      assert :ok = DataStore.delete(api.id, "key1")
      assert DataStore.get(api.id, "key1") == nil
    end

    test "returns error for missing key", %{api: api} do
      assert {:error, :not_found} = DataStore.delete(api.id, "nonexistent")
    end
  end

  describe "isolation by api_id" do
    test "entries are scoped to their API", %{org: org, user: user} do
      {:ok, api_a} =
        Apis.create_api(%{
          name: "API A",
          template_type: "crud",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      {:ok, api_b} =
        Apis.create_api(%{
          name: "API B",
          template_type: "crud",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      {:ok, _} = DataStore.put(api_a.id, "key1", %{"from" => "A"})
      {:ok, _} = DataStore.put(api_b.id, "key1", %{"from" => "B"})

      assert DataStore.get(api_a.id, "key1").value == %{"from" => "A"}
      assert DataStore.get(api_b.id, "key1").value == %{"from" => "B"}

      assert length(DataStore.list(api_a.id)) == 1
      assert length(DataStore.list(api_b.id)) == 1
    end
  end
end
