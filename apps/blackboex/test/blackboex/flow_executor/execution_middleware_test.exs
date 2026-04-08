defmodule Blackboex.FlowExecutor.ExecutionMiddlewareTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.Flows

  # Ensure node type atoms exist for DefinitionParser.safe_to_atom/1
  _ = :elixir_code
  _ = :condition

  setup do
    {user, org} = user_and_org_fixture()
    flow = flow_fixture(%{user: user, org: org})
    %{user: user, org: org, flow: flow}
  end

  defp set_definition!(flow, definition) do
    {:ok, flow} = Flows.update_definition(flow, definition)
    flow
  end

  defp linear_definition(code) do
    %{
      "version" => "1.0",
      "nodes" => [
        %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
        %{
          "id" => "n2",
          "type" => "elixir_code",
          "position" => %{"x" => 200, "y" => 0},
          "data" => %{"code" => code}
        },
        %{"id" => "n3", "type" => "end", "position" => %{"x" => 400, "y" => 0}, "data" => %{}}
      ],
      "edges" => [
        %{
          "id" => "e1",
          "source" => "n1",
          "source_port" => 0,
          "target" => "n2",
          "target_port" => 0
        },
        %{
          "id" => "e2",
          "source" => "n2",
          "source_port" => 0,
          "target" => "n3",
          "target_port" => 0
        }
      ]
    }
  end

  describe "NodeExecution persistence" do
    test "creates NodeExecution records for each node during execution", %{flow: flow} do
      code = ~s|String.upcase(input["name"])|
      flow = set_definition!(flow, linear_definition(code))

      {:ok, execution} = FlowExecutions.create_execution(flow, %{"name" => "test"})
      assert {:ok, _result} = FlowExecutor.run(flow, %{"name" => "test"}, execution.id)

      exec = FlowExecutions.get_execution(execution.id)
      assert length(exec.node_executions) == 3

      node_types = Enum.map(exec.node_executions, & &1.node_type) |> Enum.sort()
      assert node_types == ["elixir_code", "end", "start"]

      assert Enum.all?(exec.node_executions, &(&1.status == "completed"))

      assert Enum.all?(
               exec.node_executions,
               &(is_integer(&1.duration_ms) and &1.duration_ms >= 0)
             )
    end

    test "records failed node execution on error", %{flow: flow} do
      code = ~s|raise "middleware boom"|
      flow = set_definition!(flow, linear_definition(code))

      {:ok, execution} = FlowExecutions.create_execution(flow, %{})
      assert {:error, _} = FlowExecutor.run(flow, %{}, execution.id)

      exec = FlowExecutions.get_execution(execution.id)

      failed_nodes =
        Enum.filter(exec.node_executions, &(&1.status == "failed"))

      assert [failed_node | _] = failed_nodes
      assert failed_node.node_type == "elixir_code"
      assert failed_node.error =~ "middleware boom"
    end

    test "updates shared_state on FlowExecution", %{flow: flow} do
      code = ~s|{input, Map.put(state, "updated", true)}|
      flow = set_definition!(flow, linear_definition(code))

      {:ok, execution} = FlowExecutions.create_execution(flow, %{})
      assert {:ok, _} = FlowExecutor.run(flow, %{}, execution.id)

      exec = FlowExecutions.get_execution(execution.id)
      assert exec.shared_state["updated"] == true
    end
  end

  describe "PubSub broadcasts" do
    test "broadcasts node_started, node_completed, flow_completed", %{flow: flow} do
      code = ~s|input|
      flow = set_definition!(flow, linear_definition(code))

      {:ok, execution} = FlowExecutions.create_execution(flow, %{})

      # Subscribe before running
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_execution:#{execution.id}")

      assert {:ok, _} = FlowExecutor.run(flow, %{}, execution.id)

      # Expect at least one node_started and node_completed
      assert_receive {:node_started, %{node_id: _}}, 1_000
      assert_receive {:node_completed, %{node_id: _}}, 1_000
      execution_id = execution.id
      assert_receive {:flow_completed, %{execution_id: ^execution_id}}, 1_000
    end
  end

  describe "execution status transitions" do
    test "middleware marks execution as running on init", %{flow: flow} do
      code = ~s|input|
      flow = set_definition!(flow, linear_definition(code))

      {:ok, execution} = FlowExecutions.create_execution(flow, %{})
      assert execution.status == "pending"

      # Subscribe to capture the moment it transitions
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "flow_execution:#{execution.id}")

      assert {:ok, _} = FlowExecutor.run(flow, %{}, execution.id)

      # After run, the middleware should have set status to "running"
      # (the caller is responsible for setting "completed"/"failed")
      exec = FlowExecutions.get_execution(execution.id)
      # Status is "running" because run/3 doesn't update to completed — only execute_sync does
      assert exec.status == "running"
    end
  end
end
