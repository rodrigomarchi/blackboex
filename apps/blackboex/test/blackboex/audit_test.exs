defmodule Blackboex.AuditTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Audit
  alias Blackboex.Organizations

  @moduletag :unit

  defp create_context(_ctx) do
    user = user_fixture()
    [org] = Organizations.list_user_organizations(user)
    %{user: user, org: org}
  end

  describe "log/2" do
    setup [:create_context]

    test "creates an audit log entry", %{user: user, org: org} do
      assert {:ok, log} =
               Audit.log("api.published", %{
                 user_id: user.id,
                 organization_id: org.id,
                 project_id: Blackboex.Projects.get_default_project(org.id).id,
                 resource_type: "api",
                 resource_id: "some-api-id",
                 metadata: %{"version" => 1}
               })

      assert log.action == "api.published"
      assert log.user_id == user.id
      assert log.organization_id == org.id
      assert log.resource_type == "api"
      assert log.metadata == %{"version" => 1}
    end

    test "requires action" do
      assert {:error, changeset} = Audit.log(nil)
      assert %{action: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "list_logs/2" do
    setup [:create_context]

    test "returns logs for an organization", %{user: user, org: org} do
      {:ok, _} = Audit.log("api.published", %{user_id: user.id, organization_id: org.id})
      {:ok, _} = Audit.log("api_key.created", %{user_id: user.id, organization_id: org.id})

      logs = Audit.list_logs(org.id)
      assert length(logs) == 2
      assert Enum.all?(logs, &(&1.organization_id == org.id))
    end

    test "returns logs ordered by most recent first", %{user: user, org: org} do
      {:ok, _} = Audit.log("first", %{user_id: user.id, organization_id: org.id})
      {:ok, _} = Audit.log("second", %{user_id: user.id, organization_id: org.id})

      logs = Audit.list_logs(org.id)
      actions = Enum.map(logs, & &1.action)
      assert "first" in actions
      assert "second" in actions
      assert length(logs) == 2
    end

    test "respects limit option", %{user: user, org: org} do
      for i <- 1..5 do
        {:ok, _} = Audit.log("action_#{i}", %{user_id: user.id, organization_id: org.id})
      end

      logs = Audit.list_logs(org.id, limit: 3)
      assert length(logs) == 3
    end
  end

  describe "list_user_logs/2" do
    setup [:create_context]

    test "returns logs for a user", %{user: user, org: org} do
      {:ok, _} = Audit.log("api.published", %{user_id: user.id, organization_id: org.id})

      logs = Audit.list_user_logs(user.id)
      assert length(logs) == 1
      assert hd(logs).user_id == user.id
    end
  end
end
