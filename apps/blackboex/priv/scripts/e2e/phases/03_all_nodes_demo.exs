defmodule E2E.Phase.AllNodesDemo do
  import E2E.Helpers

  def run(user, org, notif_flow) do
    IO.puts(cyan("\n▸ Phase 3: All Nodes Demo (auto-approve branch)"))

    # Create all_nodes_demo from template, patch sub_flow node with real notification flow_id
    demo_flow = create_and_activate_all_nodes_demo("E2E AllNodes", user, org, notif_flow.id)

    results = [
      run_test("AllNodes: auto-approve with items", fn ->
        {:ok, resp} =
          webhook_post(demo_flow.webhook_token, %{
            "name" => "Demo",
            "email" => "demo@test.com",
            "items" => ["alpha", "beta", "gamma"],
            "needs_approval" => false
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["greeting"], "Hello, Demo!", "greeting")

        assert_eq!(
          output["approval_status"],
          "pending",
          "approval_status stays pending on auto-approve"
        )

        :ok
      end),
      run_test("AllNodes: auto-approve empty items", fn ->
        {:ok, resp} =
          webhook_post(demo_flow.webhook_token, %{
            "name" => "Empty",
            "needs_approval" => false
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["greeting"], "Hello, Empty!", "greeting")
        :ok
      end),
      run_test("AllNodes: execution has node records for all executed nodes", fn ->
        {:ok, resp} =
          webhook_post(demo_flow.webhook_token, %{
            "name" => "NodeCheck",
            "email" => "check@test.com",
            "items" => ["x"],
            "needs_approval" => false
          })

        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        assert_eq!(exec.status, "completed", "execution status")

        # Auto-approve branch: start → prepare → condition → http_request → delay → sub_flow → end
        # Plus branch-gated nodes that get skipped
        node_types = Enum.map(exec.node_executions, & &1.node_type)

        assert_present!(
          Enum.find(node_types, &(&1 == "http_request")),
          "http_request node executed"
        )

        assert_present!(Enum.find(node_types, &(&1 == "delay")), "delay node executed")
        assert_present!(Enum.find(node_types, &(&1 == "sub_flow")), "sub_flow node executed")
        :ok
      end)
    ]

    results
  end

  def stress_scenarios, do: []

  defp create_and_activate_all_nodes_demo(name_prefix, user, org, notif_flow_id) do
    ts = System.system_time(:second)
    name = "#{name_prefix} #{ts}"

    # Create from template
    {:ok, flow} =
      Blackboex.Flows.create_flow_from_template(
        %{name: name, organization_id: org.id, user_id: user.id},
        "all_nodes_demo"
      )

    # Patch the sub_flow node (n9) with the real notification flow_id
    definition = flow.definition

    patched_nodes =
      Enum.map(definition["nodes"], fn
        %{"id" => "n9", "type" => "sub_flow"} = node ->
          put_in(node, ["data", "flow_id"], notif_flow_id)

        node ->
          node
      end)

    {:ok, flow} =
      Blackboex.Flows.update_definition(flow, %{definition | "nodes" => patched_nodes})

    {:ok, flow} = Blackboex.Flows.activate_flow(flow)
    IO.puts("  Created+activated: #{flow.name} (token: #{flow.webhook_token})")
    flow
  end
end
