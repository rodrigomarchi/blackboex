defmodule Blackboex.FlowsTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Flows
  alias Blackboex.Flows.Flow

  setup do
    {user, org} = user_and_org_fixture()
    %{user: user, org: org}
  end

  describe "create_flow/1" do
    test "creates a flow with valid attrs", %{user: user, org: org} do
      attrs = %{name: "My Flow", organization_id: org.id, user_id: user.id}
      assert {:ok, %Flow{} = flow} = Flows.create_flow(attrs)
      assert flow.name == "My Flow"
      assert flow.slug == "my-flow"
      assert flow.status == "draft"
      assert flow.definition == %{}
      assert flow.organization_id == org.id
      assert flow.user_id == user.id
    end

    test "auto-generates slug from name", %{user: user, org: org} do
      attrs = %{name: "Hello World Flow!", organization_id: org.id, user_id: user.id}
      assert {:ok, flow} = Flows.create_flow(attrs)
      assert flow.slug == "hello-world-flow"
    end

    test "rejects blank name", %{user: user, org: org} do
      attrs = %{name: "", organization_id: org.id, user_id: user.id}
      assert {:error, changeset} = Flows.create_flow(attrs)
      assert %{name: _} = errors_on(changeset)
    end

    test "rejects duplicate slug within org", %{user: user, org: org} do
      attrs = %{name: "Duplicate", organization_id: org.id, user_id: user.id}
      assert {:ok, _} = Flows.create_flow(attrs)
      assert {:error, changeset} = Flows.create_flow(attrs)
      assert %{organization_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same slug in different orgs", %{user: user, org: org} do
      org2 = org_fixture(%{user: user})
      attrs1 = %{name: "Same Name", organization_id: org.id, user_id: user.id}
      attrs2 = %{name: "Same Name", organization_id: org2.id, user_id: user.id}
      assert {:ok, _} = Flows.create_flow(attrs1)
      assert {:ok, _} = Flows.create_flow(attrs2)
    end
  end

  describe "list_flows/1" do
    test "returns flows for the org", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org, name: "Listed Flow"})
      assert [found] = Flows.list_flows(org.id)
      assert found.id == flow.id
    end

    test "does not return flows from other orgs", %{user: user, org: org} do
      org2 = org_fixture(%{user: user})
      flow_fixture(%{user: user, org: org2, name: "Other Org Flow"})
      assert [] = Flows.list_flows(org.id)
    end
  end

  describe "list_flows/2 with search" do
    test "filters by name", %{user: user, org: org} do
      flow_fixture(%{user: user, org: org, name: "Payment Flow"})
      flow_fixture(%{user: user, org: org, name: "Auth Flow"})

      results = Flows.list_flows(org.id, search: "Payment")
      assert length(results) == 1
      assert hd(results).name == "Payment Flow"
    end

    test "filters by description", %{user: user, org: org} do
      flow_fixture(%{user: user, org: org, name: "Flow A", description: "handles payments"})
      flow_fixture(%{user: user, org: org, name: "Flow B", description: "handles auth"})

      results = Flows.list_flows(org.id, search: "payments")
      assert length(results) == 1
      assert hd(results).name == "Flow A"
    end
  end

  describe "get_flow/2" do
    test "returns the flow by org and id", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      assert found = Flows.get_flow(org.id, flow.id)
      assert found.id == flow.id
    end

    test "returns nil for wrong org", %{user: user, org: org} do
      org2 = org_fixture(%{user: user})
      flow = flow_fixture(%{user: user, org: org2})
      assert is_nil(Flows.get_flow(org.id, flow.id))
    end

    test "returns nil for nonexistent id", %{org: org} do
      assert is_nil(Flows.get_flow(org.id, Ecto.UUID.generate()))
    end
  end

  describe "update_flow/2" do
    test "updates name and description", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      assert {:ok, updated} = Flows.update_flow(flow, %{name: "Renamed", description: "New desc"})
      assert updated.name == "Renamed"
      assert updated.description == "New desc"
    end

    test "rejects invalid status", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      assert {:error, changeset} = Flows.update_flow(flow, %{status: "invalid"})
      assert %{status: _} = errors_on(changeset)
    end
  end

  describe "update_definition/2" do
    test "saves the definition map", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      definition = %{"drawflow" => %{"Home" => %{"data" => %{}}}}
      assert {:ok, updated} = Flows.update_definition(flow, definition)
      assert updated.definition == definition
    end
  end

  describe "delete_flow/1" do
    test "deletes the flow", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      assert {:ok, _} = Flows.delete_flow(flow)
      assert is_nil(Flows.get_flow(org.id, flow.id))
    end
  end

  describe "webhook_token" do
    test "auto-generates webhook_token on create", %{user: user, org: org} do
      attrs = %{name: "Token Flow", organization_id: org.id, user_id: user.id}
      assert {:ok, flow} = Flows.create_flow(attrs)
      assert is_binary(flow.webhook_token)
      assert String.length(flow.webhook_token) == 32
    end

    test "generates unique tokens for different flows", %{user: user, org: org} do
      assert {:ok, flow1} =
               Flows.create_flow(%{name: "Flow 1", organization_id: org.id, user_id: user.id})

      assert {:ok, flow2} =
               Flows.create_flow(%{name: "Flow 2", organization_id: org.id, user_id: user.id})

      refute flow1.webhook_token == flow2.webhook_token
    end
  end

  describe "get_flow_by_token!/1" do
    test "returns the flow matching the token", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      found = Flows.get_flow_by_token!(flow.webhook_token)
      assert found.id == flow.id
    end

    test "raises for nonexistent token" do
      assert_raise Ecto.NoResultsError, fn ->
        Flows.get_flow_by_token!("nonexistent_token_value")
      end
    end
  end

  describe "regenerate_webhook_token/1" do
    test "generates a new token", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      old_token = flow.webhook_token

      assert {:ok, updated} = Flows.regenerate_webhook_token(flow)
      assert is_binary(updated.webhook_token)
      refute updated.webhook_token == old_token
    end

    test "old token no longer works after regeneration", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      old_token = flow.webhook_token

      assert {:ok, _updated} = Flows.regenerate_webhook_token(flow)

      assert_raise Ecto.NoResultsError, fn ->
        Flows.get_flow_by_token!(old_token)
      end
    end
  end
end
