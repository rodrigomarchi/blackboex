defmodule Blackboex.FlowExecutor.ExecutionMiddlewareTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.FlowExecutor.ExecutionMiddleware
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

    test "merges shared_state atomically (new keys preserved, existing keys not lost)", %{
      flow: flow
    } do
      # Pre-seed shared_state with an existing key via direct merge
      code = ~s|{input, Map.put(state, "step_two", "done")}|
      flow = set_definition!(flow, linear_definition(code))

      {:ok, execution} = FlowExecutions.create_execution(flow, %{})
      # Pre-seed a key that the flow code won't touch
      FlowExecutions.merge_shared_state(execution.id, %{"pre_existing" => "keep_me"})

      assert {:ok, _} = FlowExecutor.run(flow, %{}, execution.id)

      exec = FlowExecutions.get_execution(execution.id)
      # The node added "step_two" via merge — pre_existing should still be there
      assert exec.shared_state["step_two"] == "done"
      assert exec.shared_state["pre_existing"] == "keep_me"
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

  describe "process context propagation" do
    test "get_process_context/0 returns current process context" do
      # Set a known value in process dictionary under OTel key
      Process.put(:otel_ctx, %{span_id: "test-span-123"})

      context = ExecutionMiddleware.get_process_context()
      assert context == %{span_id: "test-span-123"}
    after
      Process.delete(:otel_ctx)
    end

    test "get_process_context/0 returns nil when no context set" do
      Process.delete(:otel_ctx)
      context = ExecutionMiddleware.get_process_context()
      assert is_nil(context)
    end

    test "set_process_context/1 restores context in process" do
      otel_ctx = %{span_id: "restored-span", trace_id: "trace-456"}

      :ok = ExecutionMiddleware.set_process_context(otel_ctx)
      assert Process.get(:otel_ctx) == otel_ctx
    after
      Process.delete(:otel_ctx)
    end

    test "set_process_context/1 handles nil context" do
      :ok = ExecutionMiddleware.set_process_context(nil)
      assert Process.get(:otel_ctx) == nil
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
