defmodule Blackboex.PolicyTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations
  alias Blackboex.Policy

  @moduletag :unit

  defp scope_with_role(role) do
    owner = user_fixture()

    {:ok, %{organization: org, membership: membership}} =
      Organizations.create_organization(owner, %{name: "test org #{abs(System.unique_integer())}"})

    user =
      if role == :owner do
        owner
      else
        member = user_fixture()
        {:ok, _} = Organizations.add_member(org, member, role)
        member
      end

    membership =
      if role == :owner do
        membership
      else
        Organizations.get_user_membership(org, user)
      end

    scope =
      user
      |> Scope.for_user()
      |> Scope.with_organization(org, membership)

    {scope, org}
  end

  describe "owner permissions" do
    test "owner can manage any resource in their org" do
      {scope, org} = scope_with_role(:owner)

      assert Policy.authorize?(:organization_create, scope, org)
      assert Policy.authorize?(:organization_read, scope, org)
      assert Policy.authorize?(:organization_update, scope, org)
      assert Policy.authorize?(:organization_delete, scope, org)
      assert Policy.authorize?(:membership_create, scope, org)
      assert Policy.authorize?(:membership_read, scope, org)
      assert Policy.authorize?(:membership_update, scope, org)
      assert Policy.authorize?(:membership_delete, scope, org)
    end
  end

  describe "admin permissions" do
    test "admin can CRUD on organization and membership" do
      {scope, org} = scope_with_role(:admin)

      assert Policy.authorize?(:organization_read, scope, org)
      assert Policy.authorize?(:organization_create, scope, org)
      assert Policy.authorize?(:organization_update, scope, org)
      assert Policy.authorize?(:organization_delete, scope, org)
      assert Policy.authorize?(:membership_create, scope, org)
      assert Policy.authorize?(:membership_read, scope, org)
      assert Policy.authorize?(:membership_update, scope, org)
      assert Policy.authorize?(:membership_delete, scope, org)
    end
  end

  describe "member permissions" do
    test "member can read organization" do
      {scope, org} = scope_with_role(:member)

      assert Policy.authorize?(:organization_read, scope, org)
    end

    test "member can read membership" do
      {scope, org} = scope_with_role(:member)

      assert Policy.authorize?(:membership_read, scope, org)
    end

    test "member cannot create, update, or delete organization" do
      {scope, org} = scope_with_role(:member)

      refute Policy.authorize?(:organization_create, scope, org)
      refute Policy.authorize?(:organization_update, scope, org)
      refute Policy.authorize?(:organization_delete, scope, org)
    end

    test "member cannot create, update, or delete membership" do
      {scope, org} = scope_with_role(:member)

      refute Policy.authorize?(:membership_create, scope, org)
      refute Policy.authorize?(:membership_update, scope, org)
      refute Policy.authorize?(:membership_delete, scope, org)
    end
  end

  describe "api_key permissions" do
    test "owner can create, revoke, and rotate api keys" do
      {scope, org} = scope_with_role(:owner)

      assert Policy.authorize?(:api_key_create, scope, org)
      assert Policy.authorize?(:api_key_revoke, scope, org)
      assert Policy.authorize?(:api_key_rotate, scope, org)
    end

    test "admin can create, revoke, and rotate api keys" do
      {scope, org} = scope_with_role(:admin)

      assert Policy.authorize?(:api_key_create, scope, org)
      assert Policy.authorize?(:api_key_revoke, scope, org)
      assert Policy.authorize?(:api_key_rotate, scope, org)
    end

    test "member cannot create, revoke, or rotate api keys" do
      {scope, org} = scope_with_role(:member)

      refute Policy.authorize?(:api_key_create, scope, org)
      refute Policy.authorize?(:api_key_revoke, scope, org)
      refute Policy.authorize?(:api_key_rotate, scope, org)
    end
  end

  describe "api permissions" do
    test "owner can do all api actions" do
      {scope, org} = scope_with_role(:owner)

      for action <- [
            :api_create,
            :api_read,
            :api_update,
            :api_delete,
            :api_publish,
            :api_unpublish,
            :api_generate_tests,
            :api_run_tests,
            :api_generate_docs
          ] do
        assert Policy.authorize?(action, scope, org),
               "Owner should be allowed #{action}"
      end
    end

    test "admin can do all api actions" do
      {scope, org} = scope_with_role(:admin)

      for action <- [
            :api_create,
            :api_read,
            :api_update,
            :api_delete,
            :api_publish,
            :api_unpublish,
            :api_generate_tests,
            :api_run_tests,
            :api_generate_docs
          ] do
        assert Policy.authorize?(action, scope, org),
               "Admin should be allowed #{action}"
      end
    end

    test "member can create, read, update, generate_tests, run_tests, generate_docs" do
      {scope, org} = scope_with_role(:member)

      for action <- [
            :api_create,
            :api_read,
            :api_update,
            :api_generate_tests,
            :api_run_tests,
            :api_generate_docs
          ] do
        assert Policy.authorize?(action, scope, org),
               "Member should be allowed #{action}"
      end
    end

    test "member cannot delete, publish, or unpublish APIs" do
      {scope, org} = scope_with_role(:member)

      refute Policy.authorize?(:api_delete, scope, org)
      refute Policy.authorize?(:api_publish, scope, org)
      refute Policy.authorize?(:api_unpublish, scope, org)
    end
  end

  describe "authorize_and_track/3" do
    test "returns :ok for authorized action" do
      {scope, org} = scope_with_role(:owner)

      assert :ok = Policy.authorize_and_track(:organization_read, scope, org)
    end

    test "returns {:error, :unauthorized} for denied action" do
      {scope, org} = scope_with_role(:member)

      assert {:error, :unauthorized} =
               Policy.authorize_and_track(:organization_delete, scope, org)
    end

    test "emits telemetry on denied action" do
      {scope, org} = scope_with_role(:member)

      # Attach a telemetry handler to verify emission
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-policy-denied-#{inspect(ref)}",
        [:blackboex, :policy, :denied],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_fired, metadata})
        end,
        nil
      )

      Policy.authorize_and_track(:organization_delete, scope, org)

      assert_receive {:telemetry_fired, metadata}
      assert metadata.action == :organization_delete

      :telemetry.detach("test-policy-denied-#{inspect(ref)}")
    end

    test "does not emit telemetry on allowed action" do
      {scope, org} = scope_with_role(:owner)

      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-policy-allowed-#{inspect(ref)}",
        [:blackboex, :policy, :denied],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_fired, metadata})
        end,
        nil
      )

      Policy.authorize_and_track(:organization_read, scope, org)

      refute_receive {:telemetry_fired, _}, 100

      :telemetry.detach("test-policy-allowed-#{inspect(ref)}")
    end
  end

  describe "cross-org access" do
    test "user cannot access resources from another org" do
      {scope, _org} = scope_with_role(:owner)
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Organizations.create_organization(other_user, %{name: "Other Org"})

      refute Policy.authorize?(:organization_read, scope, other_org)
      refute Policy.authorize?(:organization_update, scope, other_org)
    end

    test "user cannot access APIs from another org" do
      {scope, _org} = scope_with_role(:owner)
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Organizations.create_organization(other_user, %{name: "Other Org 2"})

      refute Policy.authorize?(:api_read, scope, other_org)
      refute Policy.authorize?(:api_create, scope, other_org)
      refute Policy.authorize?(:api_delete, scope, other_org)
    end

    test "user cannot manage api_keys from another org" do
      {scope, _org} = scope_with_role(:owner)
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Organizations.create_organization(other_user, %{name: "Other Org 3"})

      refute Policy.authorize?(:api_key_create, scope, other_org)
      refute Policy.authorize?(:api_key_revoke, scope, other_org)
    end
  end
end
