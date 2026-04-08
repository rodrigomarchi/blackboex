defmodule Blackboex.FlowSecretsTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowSecrets
  alias Blackboex.FlowSecrets.FlowSecret

  setup do
    {_user, org} = user_and_org_fixture()
    %{org: org}
  end

  describe "create_secret/1" do
    test "creates a secret with valid attrs", %{org: org} do
      attrs = %{organization_id: org.id, name: "openai_key", value: "sk-test-123"}
      assert {:ok, %FlowSecret{} = secret} = FlowSecrets.create_secret(attrs)
      assert secret.name == "openai_key"
      assert secret.organization_id == org.id
      assert is_binary(secret.encrypted_value)
    end

    test "encrypts the value at rest", %{org: org} do
      {:ok, secret} =
        FlowSecrets.create_secret(%{organization_id: org.id, name: "api_key", value: "plaintext"})

      refute secret.encrypted_value == "plaintext"
      assert FlowSecret.decrypt_value(secret.encrypted_value) == "plaintext"
    end

    test "rejects invalid name (with dashes)", %{org: org} do
      attrs = %{organization_id: org.id, name: "bad-name", value: "val"}
      assert {:error, changeset} = FlowSecrets.create_secret(attrs)
      assert %{name: _} = errors_on(changeset)
    end

    test "rejects invalid name (with spaces)", %{org: org} do
      attrs = %{organization_id: org.id, name: "bad name", value: "val"}
      assert {:error, changeset} = FlowSecrets.create_secret(attrs)
      assert %{name: _} = errors_on(changeset)
    end

    test "rejects missing value", %{org: org} do
      attrs = %{organization_id: org.id, name: "my_key"}
      assert {:error, changeset} = FlowSecrets.create_secret(attrs)
      assert %{encrypted_value: _} = errors_on(changeset)
    end

    test "rejects duplicate name within org", %{org: org} do
      attrs = %{organization_id: org.id, name: "dup_key", value: "val"}
      assert {:ok, _} = FlowSecrets.create_secret(attrs)
      assert {:error, changeset} = FlowSecrets.create_secret(attrs)
      assert %{organization_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same name in different orgs", %{org: org} do
      {_user2, org2} = user_and_org_fixture()

      assert {:ok, _} =
               FlowSecrets.create_secret(%{
                 organization_id: org.id,
                 name: "shared_key",
                 value: "v1"
               })

      assert {:ok, _} =
               FlowSecrets.create_secret(%{
                 organization_id: org2.id,
                 name: "shared_key",
                 value: "v2"
               })
    end
  end

  describe "list_secrets/1" do
    test "returns secrets for the org ordered by name", %{org: org} do
      flow_secret_fixture(%{organization_id: org.id, name: "z_key", value: "v"})
      flow_secret_fixture(%{organization_id: org.id, name: "a_key", value: "v"})

      secrets = FlowSecrets.list_secrets(org.id)
      assert length(secrets) == 2
      assert Enum.map(secrets, & &1.name) == ["a_key", "z_key"]
    end

    test "does not return secrets from other orgs", %{org: org} do
      {_user2, org2} = user_and_org_fixture()
      flow_secret_fixture(%{organization_id: org2.id, name: "other_key", value: "v"})
      assert [] = FlowSecrets.list_secrets(org.id)
    end
  end

  describe "get_secret/2" do
    test "returns the secret by org and name", %{org: org} do
      flow_secret_fixture(%{organization_id: org.id, name: "my_secret", value: "val"})
      assert %FlowSecret{name: "my_secret"} = FlowSecrets.get_secret(org.id, "my_secret")
    end

    test "returns nil for unknown name", %{org: org} do
      assert is_nil(FlowSecrets.get_secret(org.id, "nonexistent"))
    end

    test "returns nil when name belongs to different org", %{org: org} do
      {_user2, org2} = user_and_org_fixture()
      flow_secret_fixture(%{organization_id: org2.id, name: "secret", value: "val"})
      assert is_nil(FlowSecrets.get_secret(org.id, "secret"))
    end
  end

  describe "get_secret_value/2" do
    test "returns decrypted value", %{org: org} do
      flow_secret_fixture(%{organization_id: org.id, name: "db_pass", value: "super_secret"})
      assert {:ok, "super_secret"} = FlowSecrets.get_secret_value(org.id, "db_pass")
    end

    test "returns error for missing secret", %{org: org} do
      assert {:error, :not_found} = FlowSecrets.get_secret_value(org.id, "missing")
    end
  end

  describe "update_secret/2" do
    test "updates the value", %{org: org} do
      secret = flow_secret_fixture(%{organization_id: org.id, name: "upd_key", value: "old"})
      assert {:ok, updated} = FlowSecrets.update_secret(secret, %{name: "upd_key", value: "new"})
      assert FlowSecret.decrypt_value(updated.encrypted_value) == "new"
    end

    test "rejects invalid name on update", %{org: org} do
      secret = flow_secret_fixture(%{organization_id: org.id, name: "valid_key", value: "v"})

      assert {:error, changeset} =
               FlowSecrets.update_secret(secret, %{name: "bad-name", value: "v"})

      assert %{name: _} = errors_on(changeset)
    end
  end

  describe "delete_secret/1" do
    test "deletes the secret", %{org: org} do
      secret = flow_secret_fixture(%{organization_id: org.id, name: "del_key", value: "v"})
      assert {:ok, _} = FlowSecrets.delete_secret(secret)
      assert is_nil(FlowSecrets.get_secret(org.id, "del_key"))
    end
  end
end
