defmodule Blackboex.FlowExecutionsTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutions.FlowExecution
  alias Blackboex.FlowExecutions.NodeExecution

  setup do
    {user, org} = user_and_org_fixture()
    flow = flow_fixture(%{user: user, org: org})
    %{user: user, org: org, flow: flow}
  end

  describe "create_execution/2" do
    test "creates a pending execution for a flow", %{flow: flow} do
      assert {:ok, %FlowExecution{} = exec} = FlowExecutions.create_execution(flow)
      assert exec.flow_id == flow.id
      assert exec.organization_id == flow.organization_id
      assert exec.status == "pending"
      assert exec.input == %{}
      assert exec.shared_state == %{}
      assert is_nil(exec.output)
    end

    test "stores input data", %{flow: flow} do
      input = %{"key" => "value"}
      assert {:ok, exec} = FlowExecutions.create_execution(flow, input)
      assert exec.input == input
    end
  end

  describe "get_execution/1" do
    test "returns execution with preloaded node_executions", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)

      {:ok, _node} =
        FlowExecutions.create_node_execution(%{
          flow_execution_id: exec.id,
          node_id: "n1",
          node_type: "http_request"
        })

      found = FlowExecutions.get_execution(exec.id)
      assert found.id == exec.id
      assert length(found.node_executions) == 1
      assert hd(found.node_executions).node_id == "n1"
    end

    test "returns nil for nonexistent id" do
      assert is_nil(FlowExecutions.get_execution(Ecto.UUID.generate()))
    end
  end

  describe "list_executions_for_flow/1" do
    test "returns executions for the flow", %{flow: flow} do
      {:ok, _exec1} = FlowExecutions.create_execution(flow)
      {:ok, _exec2} = FlowExecutions.create_execution(flow, %{"run" => 2})

      results = FlowExecutions.list_executions_for_flow(flow.id)
      assert length(results) == 2
    end

    test "returns empty list for flow with no executions", %{flow: _flow} do
      other_flow = flow_fixture()
      assert [] == FlowExecutions.list_executions_for_flow(other_flow.id)
    end
  end

  describe "complete_execution/3" do
    test "marks execution as completed with output and duration", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)
      output = %{"result" => "success"}

      assert {:ok, completed} = FlowExecutions.complete_execution(exec, output, 150)
      assert completed.status == "completed"
      assert completed.output == output
      assert completed.duration_ms == 150
      assert %DateTime{} = completed.finished_at
    end
  end

  describe "fail_execution/2" do
    test "marks execution as failed with error message", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)

      assert {:ok, failed} = FlowExecutions.fail_execution(exec, "timeout reached")
      assert failed.status == "failed"
      assert failed.error == "timeout reached"
      assert %DateTime{} = failed.finished_at
    end
  end

  describe "create_node_execution/1" do
    test "creates a node execution", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)

      attrs = %{flow_execution_id: exec.id, node_id: "n1", node_type: "http_request"}
      assert {:ok, %NodeExecution{} = node_exec} = FlowExecutions.create_node_execution(attrs)
      assert node_exec.node_id == "n1"
      assert node_exec.node_type == "http_request"
      assert node_exec.status == "pending"
    end

    test "enforces unique node_id per execution", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)

      attrs = %{flow_execution_id: exec.id, node_id: "n1", node_type: "http_request"}
      assert {:ok, _} = FlowExecutions.create_node_execution(attrs)
      assert {:error, changeset} = FlowExecutions.create_node_execution(attrs)
      assert %{flow_execution_id: _} = errors_on(changeset)
    end

    test "rejects missing required fields" do
      assert {:error, changeset} = FlowExecutions.create_node_execution(%{})
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :flow_execution_id)
      assert Map.has_key?(errors, :node_id)
      assert Map.has_key?(errors, :node_type)
    end

    test "rejects invalid status", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)

      attrs = %{
        flow_execution_id: exec.id,
        node_id: "n1",
        node_type: "http_request",
        status: "bogus"
      }

      assert {:error, changeset} = FlowExecutions.create_node_execution(attrs)
      assert %{status: _} = errors_on(changeset)
    end
  end

  describe "complete_node_execution/3" do
    test "marks node as completed", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)

      {:ok, node_exec} =
        FlowExecutions.create_node_execution(%{
          flow_execution_id: exec.id,
          node_id: "n1",
          node_type: "http_request"
        })

      output = %{"body" => "ok"}
      assert {:ok, completed} = FlowExecutions.complete_node_execution(node_exec, output, 42)
      assert completed.status == "completed"
      assert completed.output == output
      assert completed.duration_ms == 42
      assert %DateTime{} = completed.finished_at
    end
  end

  describe "fail_node_execution/2" do
    test "marks node as failed", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)

      {:ok, node_exec} =
        FlowExecutions.create_node_execution(%{
          flow_execution_id: exec.id,
          node_id: "n1",
          node_type: "http_request"
        })

      assert {:ok, failed} = FlowExecutions.fail_node_execution(node_exec, "connection refused")
      assert failed.status == "failed"
      assert failed.error == "connection refused"
      assert %DateTime{} = failed.finished_at
    end
  end

  describe "merge_shared_state/2" do
    test "merges into empty shared_state", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)
      assert exec.shared_state == %{}

      assert :ok = FlowExecutions.merge_shared_state(exec.id, %{"key" => "value"})

      updated = FlowExecutions.get_execution(exec.id)
      assert updated.shared_state == %{"key" => "value"}
    end

    test "merges into existing shared_state preserving old keys", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)
      FlowExecutions.merge_shared_state(exec.id, %{"existing" => 1})

      assert :ok = FlowExecutions.merge_shared_state(exec.id, %{"new_key" => 2})

      updated = FlowExecutions.get_execution(exec.id)
      assert updated.shared_state == %{"existing" => 1, "new_key" => 2}
    end

    test "overlapping keys: new values win", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)
      FlowExecutions.merge_shared_state(exec.id, %{"key" => "original"})

      assert :ok = FlowExecutions.merge_shared_state(exec.id, %{"key" => "updated"})

      updated = FlowExecutions.get_execution(exec.id)
      assert updated.shared_state["key"] == "updated"
    end

    test "concurrent merges of different keys do not lose data", %{flow: flow} do
      {:ok, exec} = FlowExecutions.create_execution(flow)

      task1 = Task.async(fn -> FlowExecutions.merge_shared_state(exec.id, %{"a" => 1}) end)
      task2 = Task.async(fn -> FlowExecutions.merge_shared_state(exec.id, %{"b" => 2}) end)

      Task.await(task1)
      Task.await(task2)

      updated = FlowExecutions.get_execution(exec.id)
      assert updated.shared_state["a"] == 1
      assert updated.shared_state["b"] == 2
    end

    test "returns :ok for non-existent execution_id" do
      assert :ok = FlowExecutions.merge_shared_state(Ecto.UUID.generate(), %{"x" => 1})
    end
  end

  describe "fixtures" do
    test "flow_execution_fixture creates a valid execution" do
      exec = flow_execution_fixture()
      assert exec.id
      assert exec.flow_id
      assert exec.status == "pending"
    end

    test "node_execution_fixture creates a valid node execution" do
      node_exec = node_execution_fixture()
      assert node_exec.id
      assert node_exec.node_id == "n1"
      assert node_exec.node_type == "http_request"
    end
  end
end
