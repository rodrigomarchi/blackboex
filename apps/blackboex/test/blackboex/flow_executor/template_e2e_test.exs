defmodule Blackboex.FlowExecutor.TemplateE2eTest do
  @moduledoc """
  End-to-end tests using the Hello World "Contact Router" template.

  These tests exercise the full flow pipeline:
  create from template → activate → execute (sync/async) → verify output + DB records.

  No UI screens needed — everything is validated via context functions and HTTP endpoints.
  """

  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.Flows

  setup do
    {user, org} = user_and_org_fixture()
    flow = flow_from_template_fixture(%{user: user, org: org})
    %{user: user, org: org, flow: flow}
  end

  describe "template creation" do
    test "creates flow with valid Hello World definition", %{flow: flow} do
      assert flow.status == "draft"
      assert flow.definition["version"] == "1.0"
      assert length(flow.definition["nodes"]) == 10
      assert length(flow.definition["edges"]) == 9
    end

    test "template flow can be activated", %{flow: flow} do
      assert {:ok, activated} = Flows.activate_flow(flow)
      assert activated.status == "active"
    end
  end

  # execute_sync now returns the unwrapped output directly.
  defp flow_output(result), do: result.output

  describe "sync execution — email route" do
    test "routes to email when email is provided", %{flow: flow} do
      input = %{"name" => "João", "email" => "joao@test.com"}
      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)

      output = flow_output(result)
      assert output["channel"] == "email"
      assert output["to"] == "joao@test.com"
      assert output["message"] == "Hello, João!"
      assert result.execution_id
      assert result.duration_ms >= 0
    end

    test "email takes priority when both email and phone provided", %{flow: flow} do
      input = %{"name" => "Pedro", "email" => "p@test.com", "phone" => "11999"}
      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)

      output = flow_output(result)
      assert output["channel"] == "email"
      assert output["to"] == "p@test.com"
      assert output["message"] == "Hello, Pedro!"
    end
  end

  describe "sync execution — phone route" do
    test "routes to phone when only phone is provided", %{flow: flow} do
      input = %{"name" => "Maria", "phone" => "11999887766"}
      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)

      output = flow_output(result)
      assert output["channel"] == "phone"
      assert output["to"] == "11999887766"
      assert output["message"] == "Hello, Maria!"
    end
  end

  describe "sync execution — no contact route" do
    test "returns error when no contact info provided", %{flow: flow} do
      input = %{"name" => "Ana"}
      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)

      output = flow_output(result)
      assert output["error"] == "no contact info provided"
    end
  end

  describe "sync execution — validation error" do
    test "fails when name is missing", %{flow: flow} do
      input = %{"phone" => "11999"}
      assert {:error, result} = FlowExecutor.execute_sync(flow, input)

      assert result.error =~ "name is required"
      assert result.execution_id
    end

    test "fails when name is empty string", %{flow: flow} do
      input = %{"name" => "", "email" => "test@test.com"}
      assert {:error, result} = FlowExecutor.execute_sync(flow, input)

      assert result.error =~ "name is required"
    end
  end

  describe "FlowExecution records" do
    test "creates completed FlowExecution on success", %{flow: flow} do
      input = %{"name" => "Test", "email" => "t@test.com"}
      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      assert execution.status == "completed"
      assert execution.input == input
      assert execution.output != nil
      assert execution.duration_ms >= 0
      assert execution.finished_at != nil
    end

    test "creates failed FlowExecution on validation error", %{flow: flow} do
      input = %{"phone" => "11999"}
      {:error, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      assert execution.status == "failed"
      assert execution.error =~ "name is required"
      assert execution.finished_at != nil
    end
  end

  describe "NodeExecution records" do
    test "creates NodeExecution for each executed node in email route", %{flow: flow} do
      input = %{"name" => "Test", "email" => "t@test.com"}
      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      node_execs = execution.node_executions

      # All 10 nodes get a NodeExecution record (executed or skipped via branch gate)
      assert length(node_execs) >= 6

      # Verify executed nodes completed
      executed_ids =
        node_execs
        |> Enum.filter(&(&1.status == "completed"))
        |> Enum.map(& &1.node_id)
        |> Enum.sort()

      # start, validate, build_contact, condition, format_email, end_email
      assert "n1" in executed_ids
      assert "n2" in executed_ids
      assert "n3" in executed_ids
      assert "n4" in executed_ids
      assert "n5" in executed_ids
      assert "n8" in executed_ids

      # Verify timing
      for ne <- node_execs, ne.status == "completed" do
        assert ne.started_at != nil
      end
    end

    test "creates NodeExecution for each executed node in phone route", %{flow: flow} do
      input = %{"name" => "Test", "phone" => "123"}
      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      node_execs = execution.node_executions

      executed_ids =
        node_execs
        |> Enum.filter(&(&1.status == "completed"))
        |> Enum.map(& &1.node_id)
        |> Enum.sort()

      # start, validate, build_contact, condition, format_phone, end_phone
      assert "n1" in executed_ids
      assert "n2" in executed_ids
      assert "n3" in executed_ids
      assert "n4" in executed_ids
      assert "n6" in executed_ids
      assert "n9" in executed_ids
    end

    test "creates NodeExecution for no-contact route", %{flow: flow} do
      input = %{"name" => "Test"}
      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      node_execs = execution.node_executions

      executed_ids =
        node_execs
        |> Enum.filter(&(&1.status == "completed"))
        |> Enum.map(& &1.node_id)
        |> Enum.sort()

      # start, validate, build_contact, condition, no_contact_error, end_error
      assert "n1" in executed_ids
      assert "n2" in executed_ids
      assert "n3" in executed_ids
      assert "n4" in executed_ids
      assert "n7" in executed_ids
      assert "n10" in executed_ids
    end
  end

  describe "state accumulation" do
    # Note: shared_state in DB is persisted via ExecutionMiddleware which stores
    # the state from the last completed node's result. The state map has string keys
    # because it's built from Code.eval_string results with string-keyed maps.

    test "shared_state accumulates across nodes for email route", %{flow: flow} do
      input = %{"name" => "Test", "email" => "t@test.com"}
      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      state = execution.shared_state

      assert state["greeting"] == "Hello, Test!"
      assert state["contact_type"] == "email"
      assert state["email"] == "t@test.com"
      assert state["delivered_via"] == "email"
    end

    test "shared_state accumulates across nodes for phone route", %{flow: flow} do
      input = %{"name" => "Test", "phone" => "123456"}
      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      state = execution.shared_state

      assert state["greeting"] == "Hello, Test!"
      assert state["contact_type"] == "phone"
      assert state["phone"] == "123456"
      assert state["delivered_via"] == "phone"
    end

    test "shared_state for no-contact route", %{flow: flow} do
      input = %{"name" => "Test"}
      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      state = execution.shared_state

      assert state["greeting"] == "Hello, Test!"
      assert state["contact_type"] == "none"
      assert state["delivered_via"] == "none"
    end
  end

  describe "async execution" do
    test "creates pending execution and enqueues job", %{flow: flow} do
      input = %{"name" => "Async Test", "email" => "async@test.com"}
      assert {:ok, result} = FlowExecutor.execute_async(flow, input)
      assert result.execution_id

      # Execution starts as pending
      execution = FlowExecutions.get_execution(result.execution_id)
      assert execution.status == "pending"

      # Oban job was enqueued
      assert_enqueued(
        worker: Blackboex.Workers.FlowExecutionWorker,
        args: %{execution_id: result.execution_id, flow_id: flow.id}
      )
    end

    test "Oban worker executes flow successfully", %{flow: flow} do
      input = %{"name" => "Worker Test", "email" => "worker@test.com"}
      {:ok, result} = FlowExecutor.execute_async(flow, input)

      # Execute the worker inline
      assert :ok =
               perform_job(Blackboex.Workers.FlowExecutionWorker, %{
                 execution_id: result.execution_id,
                 flow_id: flow.id
               })

      # Verify execution completed
      execution = FlowExecutions.get_execution(result.execution_id)
      assert execution.status == "completed"
      # Output is now stored unwrapped — the mapped response or pass-through value
      assert execution.output["channel"] == "email"
      assert execution.output["message"] == "Hello, Worker Test!"
      assert execution.duration_ms >= 0
    end

    test "Oban worker handles validation error", %{flow: flow} do
      input = %{"phone" => "123"}
      {:ok, result} = FlowExecutor.execute_async(flow, input)

      # Execute the worker inline — returns error tuple
      assert {:error, _} =
               perform_job(Blackboex.Workers.FlowExecutionWorker, %{
                 execution_id: result.execution_id,
                 flow_id: flow.id
               })

      # Verify execution failed
      execution = FlowExecutions.get_execution(result.execution_id)
      assert execution.status == "failed"
      assert execution.error =~ "name is required"
    end
  end
end
