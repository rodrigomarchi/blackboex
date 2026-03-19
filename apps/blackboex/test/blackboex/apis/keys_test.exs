defmodule Blackboex.Apis.KeysTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis
  alias Blackboex.Apis.ApiKey
  alias Blackboex.Apis.Keys

  import Blackboex.AccountsFixtures

  setup do
    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org"})

    {:ok, api} =
      Apis.create_api(%{
        name: "Test API",
        organization_id: org.id,
        user_id: user.id
      })

    %{user: user, org: org, api: api}
  end

  describe "create_key/2" do
    test "generates key with bb_live_ prefix and returns plain key once", %{api: api, org: org} do
      assert {:ok, plain_key, %ApiKey{} = api_key} =
               Keys.create_key(api, %{label: "Test Key", organization_id: org.id})

      assert String.starts_with?(plain_key, "bb_live_")
      # bb_live_ (8) + 32 hex chars = 40
      assert String.length(plain_key) == 40
      assert api_key.key_prefix == String.slice(plain_key, 0, 16)
      assert api_key.api_id == api.id
      assert api_key.organization_id == org.id
      assert api_key.label == "Test Key"
      assert is_binary(api_key.key_hash)
      assert api_key.revoked_at == nil
      assert api_key.expires_at == nil
    end

    test "stores SHA-256 hash of the key", %{api: api, org: org} do
      {:ok, plain_key, api_key} =
        Keys.create_key(api, %{label: "Hash Test", organization_id: org.id})

      expected_hash = :crypto.hash(:sha256, plain_key)
      assert api_key.key_hash == expected_hash
    end
  end

  describe "verify_key/1" do
    test "returns {:ok, api_key} for valid key", %{api: api, org: org} do
      {:ok, plain_key, _api_key} =
        Keys.create_key(api, %{label: "Valid", organization_id: org.id})

      assert {:ok, %ApiKey{label: "Valid"}} = Keys.verify_key(plain_key)
    end

    test "returns {:error, :invalid} for unknown key" do
      assert {:error, :invalid} = Keys.verify_key("bb_live_nonexistent1234567890abcdef")
    end

    test "returns {:error, :revoked} for revoked key", %{api: api, org: org} do
      {:ok, plain_key, api_key} =
        Keys.create_key(api, %{label: "To Revoke", organization_id: org.id})

      {:ok, _} = Keys.revoke_key(api_key)
      assert {:error, :revoked} = Keys.verify_key(plain_key)
    end

    test "returns {:error, :expired} for expired key", %{api: api, org: org} do
      {:ok, plain_key, _api_key} =
        Keys.create_key(api, %{
          label: "Expired",
          organization_id: org.id,
          expires_at: DateTime.add(DateTime.utc_now(), -3600)
        })

      assert {:error, :expired} = Keys.verify_key(plain_key)
    end
  end

  describe "verify_key_for_api/2" do
    test "returns {:ok, api_key} when key matches api", %{api: api, org: org} do
      {:ok, plain_key, _} =
        Keys.create_key(api, %{label: "Match", organization_id: org.id})

      assert {:ok, %ApiKey{}} = Keys.verify_key_for_api(plain_key, api.id)
    end

    test "returns {:error, :invalid} when key belongs to different api", %{
      api: api,
      org: org,
      user: user
    } do
      {:ok, other_api} =
        Apis.create_api(%{
          name: "Other API",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, plain_key, _} =
        Keys.create_key(api, %{label: "Wrong API", organization_id: org.id})

      assert {:error, :invalid} = Keys.verify_key_for_api(plain_key, other_api.id)
    end
  end

  describe "list_keys/1" do
    test "returns keys for api without plain key", %{api: api, org: org} do
      {:ok, _plain, _key1} =
        Keys.create_key(api, %{label: "Key 1", organization_id: org.id})

      {:ok, _plain, _key2} =
        Keys.create_key(api, %{label: "Key 2", organization_id: org.id})

      keys = Keys.list_keys(api.id)
      assert length(keys) == 2
      assert Enum.all?(keys, &(&1.api_id == api.id))
    end
  end

  describe "revoke_key/1" do
    test "marks key as revoked", %{api: api, org: org} do
      {:ok, _plain, api_key} =
        Keys.create_key(api, %{label: "Revoke Me", organization_id: org.id})

      assert {:ok, revoked} = Keys.revoke_key(api_key)
      assert revoked.revoked_at != nil
    end
  end

  describe "rotate_key/1" do
    test "revokes old key and creates new one", %{api: api, org: org} do
      {:ok, old_plain, old_key} =
        Keys.create_key(api, %{label: "Old Key", organization_id: org.id})

      assert {:ok, new_plain, new_key} = Keys.rotate_key(old_key)
      assert new_plain != old_plain
      assert new_key.id != old_key.id
      assert new_key.api_id == api.id

      # Old key should be revoked
      assert {:error, :revoked} = Keys.verify_key(old_plain)
      # New key should work
      assert {:ok, _} = Keys.verify_key(new_plain)
    end
  end

  describe "touch_last_used/1" do
    test "updates last_used_at when nil", %{api: api, org: org} do
      {:ok, _plain, api_key} =
        Keys.create_key(api, %{label: "Touch Test", organization_id: org.id})

      assert api_key.last_used_at == nil
      :ok = Keys.touch_last_used(api_key)

      updated = Blackboex.Repo.get!(Blackboex.Apis.ApiKey, api_key.id)
      assert updated.last_used_at != nil
    end

    test "skips update when last_used_at is recent", %{api: api, org: org} do
      {:ok, _plain, api_key} =
        Keys.create_key(api, %{label: "Recent", organization_id: org.id})

      # First touch
      :ok = Keys.touch_last_used(api_key)
      updated = Blackboex.Repo.get!(Blackboex.Apis.ApiKey, api_key.id)
      first_touch = updated.last_used_at

      # Second touch within 60s — should NOT update
      :ok = Keys.touch_last_used(updated)
      same = Blackboex.Repo.get!(Blackboex.Apis.ApiKey, api_key.id)
      assert same.last_used_at == first_touch
    end
  end

  describe "cascade delete" do
    test "deleting API removes its keys", %{api: api, org: org} do
      {:ok, _plain, _key} =
        Keys.create_key(api, %{label: "Cascade", organization_id: org.id})

      assert length(Keys.list_keys(api.id)) == 1

      Blackboex.Repo.delete!(api)

      assert Keys.list_keys(api.id) == []
    end
  end
end
