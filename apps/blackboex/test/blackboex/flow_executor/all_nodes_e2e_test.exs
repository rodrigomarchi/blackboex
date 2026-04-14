defmodule Blackboex.FlowExecutor.AllNodesE2eTest do
  @moduledoc """
  End-to-end tests for the All Nodes Demo flow.

  Exercises all 9 node types across two branches:
    Branch 0 (needs approval):  start → elixir_code → condition(0) → webhook_wait (halts)
    Branch 1 (auto-approve):    start → elixir_code → condition(1) → http_request → delay → sub_flow → end
  """

  use Blackboex.DataCase, async: false

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.FlowExecutor.BlackboexFlow
  alias Blackboex.Flows
  alias Blackboex.Flows.Templates.AllNodesDemo
  alias Blackboex.Flows.Templates.Notification

  # ── Setup ────────────────────────────────────────────────────

  setup do
    {user, org} = user_and_org_fixture()

    # Create the notification sub-flow (used by the sub_flow node)
    notification_def = Notification.definition()

    {:ok, notification_flow} =
      Flows.create_flow(%{
        name: "Notification Sub-Flow",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id,
        definition: notification_def
      })

    # Create the main flow with the all-nodes-demo definition.
    # Patch sub_flow ID and shorten delay — these are JSON-safe values.
    definition = build_db_definition(notification_flow.id)

    {:ok, flow} =
      Flows.create_flow(%{
        name: "All Nodes Demo",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id,
        definition: definition
      })

    # Inject test HTTP plug in-memory (tuples can't be stored as JSON).
    flow = inject_test_plug(flow)

    %{user: user, org: org, flow: flow, notification_flow: notification_flow}
  end

  # ── Branch 1: Auto-Approve (needs_approval=false) ───────────

  describe "branch 1 — auto-approve path" do
    test "executes start → code → condition → http_request → delay → sub_flow → end",
         %{flow: flow} do
      stub_http_response()

      input = %{
        "name" => "Rodrigo",
        "email" => "rodrigo@test.com",
        "items" => ["a", "b"],
        "needs_approval" => false
      }

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)
      refute Map.has_key?(result, :halted)
      assert result.execution_id
      assert result.duration_ms >= 0

      output = result.output
      assert output["greeting"] == "Hello, Rodrigo!"
    end

    test "creates NodeExecution records for all executed nodes", %{flow: flow} do
      stub_http_response()

      input = %{
        "name" => "Test",
        "email" => "t@test.com",
        "items" => ["x"],
        "needs_approval" => false
      }

      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      node_execs = execution.node_executions

      completed_ids =
        node_execs
        |> Enum.filter(&(&1.status == "completed"))
        |> Enum.map(& &1.node_id)
        |> MapSet.new()

      # Branch 1 path: n1(start), n2(code), n3(condition), n7(http), n8(delay), n9(sub_flow), n10(end)
      for id <- ~w(n1 n2 n3 n7 n8 n9 n10) do
        assert id in completed_ids,
               "expected #{id} to be completed, got: #{inspect(completed_ids)}"
      end

      # All executed nodes have timing info
      for ne <- node_execs, ne.status == "completed" do
        assert ne.started_at != nil
      end
    end

    test "shared_state accumulates across nodes", %{flow: flow} do
      stub_http_response()

      input = %{
        "name" => "State",
        "email" => "s@test.com",
        "items" => ["a"],
        "needs_approval" => false
      }

      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      state = execution.shared_state

      # elixir_code node sets greeting
      assert state["greeting"] == "Hello, State!"
      # http_request node sets http_response
      assert is_map(state["http_response"])
      # delay node sets delayed_ms
      assert is_integer(state["delayed_ms"])
      # sub_flow node sets sub_flow_result
      assert state["sub_flow_result"] != nil
    end

    test "http_request receives correct response", %{flow: flow} do
      stub_http_response()

      input = %{
        "name" => "HTTP",
        "items" => ["a"],
        "needs_approval" => false
      }

      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      http_resp = execution.shared_state["http_response"]

      assert http_resp["status"] == 200
      assert http_resp["body"]["origin"] == "test"
    end

    test "sub_flow executes notification and merges result", %{flow: flow} do
      stub_http_response()

      input = %{
        "name" => "SubFlow",
        "items" => [],
        "needs_approval" => false
      }

      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      sub_result = execution.shared_state["sub_flow_result"]

      # The notification sub-flow formats: "Notification via <channel>: <message>"
      assert is_binary(sub_result) or is_map(sub_result)
    end
  end

  # ── Branch 0: Needs Approval (needs_approval=true) ──────────

  describe "branch 0 — needs-approval path (webhook_wait halts)" do
    test "halts at webhook_wait node", %{flow: flow} do
      input = %{
        "name" => "Approval",
        "items" => ["x", "y"],
        "needs_approval" => true
      }

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)
      assert result.halted == true
      assert result.execution_id
    end

    test "execution is marked as halted in DB", %{flow: flow} do
      input = %{
        "name" => "WaitTest",
        "items" => [],
        "needs_approval" => true
      }

      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      assert execution.status == "halted"
    end

    test "nodes before halt are completed", %{flow: flow} do
      input = %{
        "name" => "NodeCheck",
        "items" => [],
        "needs_approval" => true
      }

      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      node_execs = execution.node_executions

      completed_ids =
        node_execs
        |> Enum.filter(&(&1.status == "completed"))
        |> Enum.map(& &1.node_id)
        |> MapSet.new()

      # start, elixir_code, and condition should have completed before the halt
      for id <- ~w(n1 n2 n3) do
        assert id in completed_ids,
               "expected #{id} to be completed before halt, got: #{inspect(completed_ids)}"
      end
    end

    test "shared_state has greeting set before halt", %{flow: flow} do
      input = %{
        "name" => "Greeting",
        "items" => [],
        "needs_approval" => true
      }

      {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      assert execution.shared_state["greeting"] == "Hello, Greeting!"
    end
  end

  # ── Validation ──────────────────────────────────────────────

  describe "template validation" do
    test "template definition passes BlackboexFlow.validate/1" do
      definition = AllNodesDemo.definition()
      assert :ok = BlackboexFlow.validate(definition)
    end

    test "notification template definition passes BlackboexFlow.validate/1" do
      definition = Notification.definition()
      assert :ok = BlackboexFlow.validate(definition)
    end
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp stub_http_response do
    Req.Test.stub(:all_nodes_e2e, fn conn ->
      body = Jason.encode!(%{"origin" => "test", "url" => conn.request_path})

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, body)
    end)
  end

  # Builds a JSON-safe definition for DB storage (no tuples).
  defp build_db_definition(notification_flow_id) do
    base = AllNodesDemo.definition()

    nodes =
      Enum.map(base["nodes"], fn node ->
        case node["type"] do
          "sub_flow" ->
            node
            |> put_in(["data", "flow_id"], notification_flow_id)
            |> put_in(["data", "input_mapping"], %{
              "message" => "state[\"greeting\"]",
              "channel" => "\"email\""
            })

          "delay" ->
            put_in(node, ["data", "duration_ms"], 10)

          _ ->
            node
        end
      end)

    Map.put(base, "nodes", nodes)
  end

  # Injects {Req.Test, :all_nodes_e2e} plug into the http_request node
  # in-memory only (tuples can't be stored as JSON in Postgres).
  defp inject_test_plug(flow) do
    nodes =
      Enum.map(flow.definition["nodes"], fn node ->
        case node["type"] do
          "http_request" -> put_in(node, ["data", "plug"], {Req.Test, :all_nodes_e2e})
          _ -> node
        end
      end)

    definition = Map.put(flow.definition, "nodes", nodes)
    %{flow | definition: definition}
  end
end
