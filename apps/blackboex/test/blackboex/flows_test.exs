defmodule Blackboex.FlowsTest do
  use Blackboex.DataCase, async: true

  # Some tests intentionally feed invalid definitions into record_ai_edit and
  # similar, which logs warnings about the changeset failure.
  @moduletag :capture_log

  alias Blackboex.Flows
  alias Blackboex.Flows.Flow

  setup do
    {user, org} = user_and_org_fixture()
    %{user: user, org: org}
  end

  describe "create_flow/1 ownership" do
    test "rejects cross-org project (T7 IDOR)", %{user: user, org: org_a} do
      org_b = org_fixture(%{user: user})
      project_b = project_fixture(%{user: user, org: org_b})

      assert {:error, :forbidden} =
               Flows.create_flow(%{
                 name: "Hack",
                 organization_id: org_a.id,
                 project_id: project_b.id,
                 user_id: user.id
               })
    end
  end

  describe "create_flow/1" do
    test "creates a flow with valid attrs", %{user: user, org: org} do
      attrs = %{
        name: "My Flow",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, %Flow{} = flow} = Flows.create_flow(attrs)
      assert flow.name == "My Flow"
      assert flow.slug =~ ~r/^my-flow-[a-z0-9]{6}$/
      assert flow.status == "draft"
      assert flow.definition == %{}
      assert flow.organization_id == org.id
      assert flow.user_id == user.id
    end

    test "auto-generates slug from name", %{user: user, org: org} do
      attrs = %{
        name: "Hello World Flow!",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, flow} = Flows.create_flow(attrs)
      assert flow.slug =~ ~r/^hello-world-flow-[a-z0-9]{6}$/
    end

    test "rejects blank name", %{user: user, org: org} do
      attrs = %{
        name: "",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:error, changeset} = Flows.create_flow(attrs)
      assert %{name: _} = errors_on(changeset)
    end

    test "rejects duplicate slug within project", %{user: user, org: org} do
      project_id = Blackboex.Projects.get_default_project(org.id).id

      attrs = %{
        name: "Duplicate",
        slug: "duplicate-slug",
        organization_id: org.id,
        project_id: project_id,
        user_id: user.id
      }

      assert {:ok, _} = Flows.create_flow(attrs)
      assert {:error, changeset} = Flows.create_flow(attrs)
      assert %{project_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same slug in different orgs", %{user: user, org: org} do
      org2 = org_fixture(%{user: user})

      attrs1 = %{
        name: "Same Name",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      attrs2 = %{
        name: "Same Name",
        organization_id: org2.id,
        project_id: Blackboex.Projects.get_default_project(org2.id).id,
        user_id: user.id
      }

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
    test "saves a valid definition", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})

      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{"id" => "n2", "type" => "end", "position" => %{"x" => 200, "y" => 0}, "data" => %{}}
        ],
        "edges" => [
          %{
            "id" => "e1",
            "source" => "n1",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          }
        ]
      }

      assert {:ok, updated} = Flows.update_definition(flow, definition)
      assert updated.definition["version"] == "1.0"
    end

    test "rejects invalid definition structure", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      definition = %{"drawflow" => %{"Home" => %{"data" => %{}}}}
      assert {:error, changeset} = Flows.update_definition(flow, definition)
      assert %{definition: _} = errors_on(changeset)
    end
  end

  describe "record_ai_edit/3" do
    setup %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      scope = %{organization: %{id: org.id}}
      %{flow: flow, scope: scope}
    end

    test "updates the flow definition when scope org matches", %{flow: flow, scope: scope} do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{"id" => "n2", "type" => "end", "position" => %{"x" => 200, "y" => 0}, "data" => %{}}
        ],
        "edges" => [
          %{
            "id" => "e1",
            "source" => "n1",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          }
        ]
      }

      assert {:ok, updated} = Flows.record_ai_edit(flow, definition, scope)
      assert updated.definition["version"] == "1.0"
      assert length(updated.definition["nodes"]) == 2
    end

    test "rejects when scope org mismatches flow org", %{flow: flow, user: user} do
      other_org = org_fixture(%{user: user})
      scope = %{organization: %{id: other_org.id}}

      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{"id" => "n2", "type" => "end", "position" => %{"x" => 200, "y" => 0}, "data" => %{}}
        ],
        "edges" => [
          %{
            "id" => "e1",
            "source" => "n1",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          }
        ]
      }

      assert {:error, :unauthorized} = Flows.record_ai_edit(flow, definition, scope)
    end

    test "propagates validation errors from BlackboexFlow.validate",
         %{flow: flow, scope: scope} do
      definition = %{"version" => "9.99", "nodes" => [], "edges" => []}
      assert {:error, changeset} = Flows.record_ai_edit(flow, definition, scope)
      assert %{definition: _} = errors_on(changeset)
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
      attrs = %{
        name: "Token Flow",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, flow} = Flows.create_flow(attrs)
      assert is_binary(flow.webhook_token)
      assert String.length(flow.webhook_token) == 32
    end

    test "generates unique tokens for different flows", %{user: user, org: org} do
      assert {:ok, flow1} =
               Flows.create_flow(%{
                 name: "Flow 1",
                 organization_id: org.id,
                 project_id: Blackboex.Projects.get_default_project(org.id).id,
                 user_id: user.id
               })

      assert {:ok, flow2} =
               Flows.create_flow(%{
                 name: "Flow 2",
                 organization_id: org.id,
                 project_id: Blackboex.Projects.get_default_project(org.id).id,
                 user_id: user.id
               })

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

  describe "activate_flow/1" do
    test "activates a flow with valid definition", %{user: user, org: org} do
      flow = flow_from_template_fixture(%{user: user, org: org})
      assert {:ok, activated} = Flows.activate_flow(flow)
      assert activated.status == "active"
    end

    test "rejects activation with empty definition", %{user: user, org: org} do
      flow = flow_fixture(%{user: user, org: org})
      assert {:error, reason} = Flows.activate_flow(flow)
      assert is_binary(reason)
    end

    test "rejects activation with invalid definition", %{user: user, org: org} do
      flow =
        flow_fixture(%{
          user: user,
          org: org,
          definition: %{"version" => "1.0", "nodes" => [], "edges" => []}
        })

      assert {:error, reason} = Flows.activate_flow(flow)
      assert is_binary(reason)
    end
  end

  describe "deactivate_flow/1" do
    test "sets flow back to draft", %{user: user, org: org} do
      flow = flow_from_template_fixture(%{user: user, org: org})
      {:ok, activated} = Flows.activate_flow(flow)
      assert {:ok, deactivated} = Flows.deactivate_flow(activated)
      assert deactivated.status == "draft"
    end
  end

  describe "create_flow_from_template/2" do
    test "creates flow with template definition", %{user: user, org: org} do
      attrs = %{
        name: "From Template",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:ok, flow} = Flows.create_flow_from_template(attrs, "hello_world")
      assert flow.name == "From Template"
      assert flow.status == "draft"
      assert flow.definition["version"] == "1.0"
      assert length(flow.definition["nodes"]) == 10
      assert length(flow.definition["edges"]) == 9
    end

    test "returns error for unknown template", %{user: user, org: org} do
      attrs = %{
        name: "Bad Template",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      }

      assert {:error, :template_not_found} = Flows.create_flow_from_template(attrs, "nonexistent")
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

  describe "list_for_project/2" do
    test "returns only flows belonging to the given project", %{user: user, org: org} do
      project_a = project_fixture(%{user: user, org: org, name: "Flow Project A"})
      project_b = project_fixture(%{user: user, org: org, name: "Flow Project B"})

      _f1 = flow_fixture(%{user: user, org: org, project: project_a, name: "Alpha Flow"})
      _f2 = flow_fixture(%{user: user, org: org, project: project_a, name: "Beta Flow"})
      _f3 = flow_fixture(%{user: user, org: org, project: project_a, name: "Gamma Flow"})
      _f4 = flow_fixture(%{user: user, org: org, project: project_b, name: "Delta Flow"})
      _f5 = flow_fixture(%{user: user, org: org, project: project_b, name: "Epsilon Flow"})

      results_a = Flows.list_for_project(project_a.id)
      results_b = Flows.list_for_project(project_b.id)

      assert length(results_a) == 3
      assert length(results_b) == 2
      assert Enum.all?(results_a, &(&1.project_id == project_a.id))
    end

    test "returns flows ordered by name ASC", %{user: user, org: org} do
      project = project_fixture(%{user: user, org: org, name: "Sorted Flows"})

      flow_fixture(%{user: user, org: org, project: project, name: "Zeta Flow"})
      flow_fixture(%{user: user, org: org, project: project, name: "Alpha Flow"})
      flow_fixture(%{user: user, org: org, project: project, name: "Mango Flow"})

      results = Flows.list_for_project(project.id)
      names = Enum.map(results, & &1.name)

      assert names == Enum.sort(names)
    end

    test "respects :limit option", %{user: user, org: org} do
      project = project_fixture(%{user: user, org: org, name: "Limited Flows"})

      flow_fixture(%{user: user, org: org, project: project, name: "Flow One"})
      flow_fixture(%{user: user, org: org, project: project, name: "Flow Two"})
      flow_fixture(%{user: user, org: org, project: project, name: "Flow Three"})

      results = Flows.list_for_project(project.id, limit: 2)

      assert length(results) == 2
    end
  end

  describe "move_flow/2" do
    test "moves flow to another project in same org", %{user: user, org: org} do
      project_a = project_fixture(%{user: user, org: org, name: "Source"})
      project_b = project_fixture(%{user: user, org: org, name: "Dest"})
      flow = flow_fixture(%{user: user, org: org, project: project_a})

      assert {:ok, updated} = Flows.move_flow(flow, project_b.id)
      assert updated.project_id == project_b.id
    end

    test "returns forbidden when destination project belongs to another org", %{
      user: user,
      org: org
    } do
      project_a = project_fixture(%{user: user, org: org, name: "Source"})
      flow = flow_fixture(%{user: user, org: org, project: project_a})

      {other_user, other_org} = user_and_org_fixture()
      other_project = project_fixture(%{user: other_user, org: other_org})

      assert {:error, :forbidden} = Flows.move_flow(flow, other_project.id)
      assert Flows.get_flow(org.id, flow.id).project_id == project_a.id
    end

    test "returns forbidden when destination project_id does not exist", %{user: user, org: org} do
      project_a = project_fixture(%{user: user, org: org, name: "Source"})
      flow = flow_fixture(%{user: user, org: org, project: project_a})
      nonexistent_id = Ecto.UUID.generate()

      assert {:error, :forbidden} = Flows.move_flow(flow, nonexistent_id)
      assert Flows.get_flow(org.id, flow.id).project_id == project_a.id
    end
  end
end
