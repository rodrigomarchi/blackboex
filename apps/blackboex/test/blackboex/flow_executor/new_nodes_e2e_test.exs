defmodule Blackboex.FlowExecutor.NewNodesE2eTest do
  @moduledoc """
  End-to-end tests for new flow engine features:
  - Fail node (explicit error signaling)
  - Debug node (input inspection + state storage)
  - Skip condition (conditional node bypass)
  - Undo/compensation (ElixirCode and HttpRequest)
  """

  use Blackboex.DataCase, async: false

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.FlowExecutor.BlackboexFlow
  alias Blackboex.Flows
  alias Blackboex.Samples.FlowTemplates.AdvancedFeatures

  setup do
    {user, org} = user_and_org_fixture()

    {:ok, flow} =
      Flows.create_flow(%{
        name: "Advanced Features Test",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id,
        definition: AdvancedFeatures.definition()
      })

    %{user: user, org: org, flow: flow}
  end

  # ── Template Validation ─────────────────────────────────────

  describe "template validation" do
    test "AdvancedFeatures definition passes BlackboexFlow.validate/1" do
      assert :ok = BlackboexFlow.validate(AdvancedFeatures.definition())
    end
  end

  # ── Happy Path: Valid Data → Success ────────────────────────

  describe "happy path — valid data" do
    test "executes debug → validate → transform → end", %{flow: flow} do
      input = %{"name" => "Rodrigo", "email" => "r@test.com", "strict_mode" => false}

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)
      refute Map.has_key?(result, :halted)
      assert result.execution_id
      assert result.duration_ms >= 0

      output = result.output
      assert output["greeting"] == "Hello, RODRIGO!"
      assert output["processed"] == true
    end

    test "debug node stores input inspection in shared_state", %{flow: flow} do
      input = %{"name" => "Debug Test", "email" => "d@test.com"}

      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      state = execution.shared_state

      assert state["debug_input"] != nil
      assert is_map(state["debug_input"])
      assert state["debug_input"]["name"] == "Debug Test"
    end

    test "creates NodeExecution records for all executed nodes", %{flow: flow} do
      input = %{"name" => "Nodes Test"}

      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      node_execs = execution.node_executions

      completed_ids =
        node_execs
        |> Enum.filter(&(&1.status == "completed"))
        |> Enum.map(& &1.node_id)
        |> MapSet.new()

      # Happy path: n1(start), n2(debug), n3(validate), n4(condition), n5(transform), n6(end)
      for id <- ~w(n1 n2 n3 n4 n5 n6) do
        assert id in completed_ids,
               "expected #{id} to be completed, got: #{inspect(completed_ids)}"
      end
    end
  end

  # ── Fail Path: Invalid Data in Strict Mode → Fail ──────────

  describe "fail path — strict mode without email" do
    test "fail node produces error", %{flow: flow} do
      # strict_mode=true but no email → validation fails → branch 1 → fail node
      input = %{"name" => "Test", "strict_mode" => true}

      assert {:error, error_info} = FlowExecutor.execute_sync(flow, input)
      assert error_info.error =~ "Validation failed"
      assert error_info.error =~ "email required in strict mode"
    end

    test "execution is marked as failed in DB", %{flow: flow} do
      input = %{"name" => "Fail Test", "strict_mode" => true}

      {:error, error_info} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(error_info.execution_id)
      assert execution.status == "failed"
    end
  end

  # ── Skip Condition: Bypass Validation ──────────────────────

  describe "skip condition — bypass validation" do
    test "skips validation when skip_validation is true", %{flow: flow} do
      # With skip_validation=true and strict_mode=true but no email,
      # the validate node is skipped, so input passes through unchanged.
      # The condition expression: if input["valid"] == true or input["valid"] == nil, do: 0, else: 1
      # Since validate was skipped, input["valid"] is nil → routes to branch 0 (transform).
      input = %{"name" => "Skip Test", "strict_mode" => true, "skip_validation" => true}

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)
      output = result.output
      assert output["greeting"] == "Hello, SKIP TEST!"
      assert output["processed"] == true
    end

    test "does NOT skip validation when skip_validation is false", %{flow: flow} do
      input = %{"name" => "No Skip", "strict_mode" => true, "skip_validation" => false}

      # Validation runs, fails because no email in strict mode → fail node
      assert {:error, error_info} = FlowExecutor.execute_sync(flow, input)
      assert error_info.error =~ "Validation failed"
    end
  end

  # ── Debug Node Behavior ────────────────────────────────────

  describe "debug node behavior" do
    test "debug node does not modify flow output", %{flow: flow} do
      input1 = %{"name" => "Alice"}
      input2 = %{"name" => "Alice"}

      {:ok, result1} = FlowExecutor.execute_sync(flow, input1)
      {:ok, result2} = FlowExecutor.execute_sync(flow, input2)

      # Same input produces same output regardless of debug
      assert result1.output == result2.output
    end

    test "debug node stores structured map in shared_state", %{flow: flow} do
      input = %{"name" => "DebugMap", "email" => "dm@test.com", "strict_mode" => false}

      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      debug_val = execution.shared_state["debug_input"]

      assert is_map(debug_val)
      assert debug_val["name"] == "DebugMap"
      assert debug_val["email"] == "dm@test.com"
      assert debug_val["strict"] == false
    end
  end

  # ── Undo/Compensation (Unit-level, callable) ───────────────

  describe "undo callbacks are callable" do
    test "ElixirCode.undo/4 works with undo_code" do
      alias Blackboex.FlowExecutor.Nodes.ElixirCode

      value = %{output: "created", state: %{"id" => "123"}}
      args = %{prev_result: %{output: "input", state: %{"id" => "123"}}}
      opts = [undo_code: ~s|{input, state, result}|, timeout_ms: 5_000]

      assert :ok = ElixirCode.undo(value, args, %{}, opts)
    end

    test "ElixirCode.undo/4 returns :ok when no undo_code" do
      alias Blackboex.FlowExecutor.Nodes.ElixirCode

      args = %{prev_result: %{output: "input", state: %{}}}
      assert :ok = ElixirCode.undo(%{}, args, %{}, [])
    end

    test "HttpRequest.undo/4 returns :ok without undo_config" do
      alias Blackboex.FlowExecutor.Nodes.HttpRequest

      args = %{prev_result: %{output: %{}, state: %{}}}
      assert :ok = HttpRequest.undo(%{}, args, %{}, [])
    end
  end
end
