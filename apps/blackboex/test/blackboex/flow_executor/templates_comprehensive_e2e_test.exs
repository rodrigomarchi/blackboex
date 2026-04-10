defmodule Blackboex.FlowExecutor.TemplatesComprehensiveE2eTest do
  @moduledoc """
  Comprehensive E2E tests exercising all new templates and node type combinations.
  Ensures every node type (including fail, debug, skip_condition) works correctly
  in realistic flow graphs.
  """

  use Blackboex.DataCase, async: false

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.FlowExecutor.BlackboexFlow
  alias Blackboex.Flows
  alias Blackboex.Flows.Templates
  alias Blackboex.Flows.Templates.LeadScoring
  alias Blackboex.Flows.Templates.WebhookProcessor

  # ── LeadScoring Template ────────────────────────────────────

  describe "LeadScoring template" do
    setup do
      {user, org} = user_and_org_fixture()

      {:ok, flow} =
        Flows.create_flow(%{
          name: "Lead Scoring E2E",
          organization_id: org.id,
          user_id: user.id,
          definition: LeadScoring.definition()
        })

      %{flow: flow}
    end

    test "template passes validation" do
      assert :ok = BlackboexFlow.validate(LeadScoring.definition())
    end

    test "qualified lead (high score) → success path", %{flow: flow} do
      input = %{
        "name" => "Alice",
        "email" => "alice@bigcorp.com",
        "company" => "BigCorp",
        "budget" => 5000
      }

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)
      output = result.output
      assert output["status"] == "qualified"
      assert output["name"] == "Alice"
      assert output["email"] == "alice@bigcorp.com"
    end

    test "qualified lead stores score in shared_state", %{flow: flow} do
      input = %{"name" => "Bob", "email" => "bob@co.com", "company" => "Co", "budget" => 2000}

      {:ok, result} = FlowExecutor.execute_sync(flow, input)
      execution = FlowExecutions.get_execution(result.execution_id)
      state = execution.shared_state

      # email(+20) + company(+30) + budget>1000(+50) = 100
      assert state["score"] == 100
      assert state["qualified"] == true
      assert state["enriched"] == true
    end

    test "unqualified lead (low score) → fail path", %{flow: flow} do
      # email only (+20), no company, no budget → score 20 < 50
      input = %{"name" => "Charlie", "email" => "charlie@test.com"}

      assert {:error, error_info} = FlowExecutor.execute_sync(flow, input)
      assert error_info.error =~ "not qualified"
    end

    test "debug node stores lead info in shared_state", %{flow: flow} do
      input = %{"name" => "Debug Lead", "email" => "d@test.com", "company" => "TestCo"}

      {:ok, result} = FlowExecutor.execute_sync(flow, input)
      execution = FlowExecutions.get_execution(result.execution_id)
      state = execution.shared_state

      assert state["debug_lead"] != nil
      assert is_map(state["debug_lead"])
      assert state["debug_lead"]["name"] == "Debug Lead"
    end

    test "skip_scoring bypasses scoring → routes to success branch", %{flow: flow} do
      # When scoring is skipped, input["qualified"] is nil → condition routes to branch 0 (success)
      input = %{"name" => "Skip", "email" => "s@test.com", "skip_scoring" => true}

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)
      assert result.output != nil
    end

    test "creates correct NodeExecution records for qualified path", %{flow: flow} do
      input = %{"name" => "Records", "email" => "r@co.com", "company" => "Co", "budget" => 2000}

      {:ok, result} = FlowExecutor.execute_sync(flow, input)
      execution = FlowExecutions.get_execution(result.execution_id)

      completed_ids =
        execution.node_executions
        |> Enum.filter(&(&1.status == "completed"))
        |> Enum.map(& &1.node_id)
        |> MapSet.new()

      # Qualified path: n1(start), n2(debug), n3(score), n4(condition), n5(enrich), n6(end)
      for id <- ~w(n1 n2 n3 n4 n5 n6) do
        assert id in completed_ids, "expected #{id} completed, got: #{inspect(completed_ids)}"
      end
    end

    test "fail node execution is recorded in DB", %{flow: flow} do
      input = %{"name" => "Failing", "email" => "fail@test.com"}

      {:error, error_info} = FlowExecutor.execute_sync(flow, input)
      execution = FlowExecutions.get_execution(error_info.execution_id)

      assert execution.status == "failed"
      assert execution.error =~ "not qualified"
    end
  end

  # ── WebhookProcessor Template ───────────────────────────────

  describe "WebhookProcessor template" do
    setup do
      {user, org} = user_and_org_fixture()

      {:ok, flow} =
        Flows.create_flow(%{
          name: "Webhook Processor E2E",
          organization_id: org.id,
          user_id: user.id,
          definition: WebhookProcessor.definition()
        })

      %{flow: flow}
    end

    test "template passes validation" do
      assert :ok = BlackboexFlow.validate(WebhookProcessor.definition())
    end

    test "order.created event → order processing path with delay", %{flow: flow} do
      input = %{
        "event_type" => "order.created",
        "payload" => %{"id" => "ORD-001", "amount" => 99.90},
        "timestamp" => "2026-04-10T12:00:00Z"
      }

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)
      output = result.output
      assert output["action"] == "order_processed"
      assert output["order_id"] == "ORD-001"
    end

    test "payment.received event → payment processing path", %{flow: flow} do
      input = %{
        "event_type" => "payment.received",
        "payload" => %{"id" => "PAY-001", "status" => "confirmed"},
        "timestamp" => "2026-04-10T12:00:00Z"
      }

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)
      output = result.output
      assert output["action"] == "payment_processed"
      assert output["payment_id"] == "PAY-001"
    end

    test "unknown event type → fail path", %{flow: flow} do
      input = %{"event_type" => "invoice.voided", "timestamp" => "2026-04-10T12:00:00Z"}

      assert {:error, error_info} = FlowExecutor.execute_sync(flow, input)
      assert error_info.error =~ "Unsupported event type"
    end

    test "test event type skips validation and routes to order path", %{flow: flow} do
      # skip_condition: input["event_type"] == "test"
      # condition expression: event_type == "order.created" or "test" → 0
      input = %{"event_type" => "test", "payload" => %{"id" => "TEST-001"}}

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)
      output = result.output
      assert output["action"] == "order_processed"
    end

    test "debug node stores event info in shared_state", %{flow: flow} do
      input = %{
        "event_type" => "order.created",
        "payload" => %{"id" => "DBG-001"},
        "timestamp" => "2026-04-10"
      }

      {:ok, result} = FlowExecutor.execute_sync(flow, input)
      execution = FlowExecutions.get_execution(result.execution_id)
      state = execution.shared_state

      assert state["debug_event"] != nil
      assert is_map(state["debug_event"])
      assert state["debug_event"]["type"] == "order.created"
    end

    test "order path includes delay node execution", %{flow: flow} do
      input = %{
        "event_type" => "order.created",
        "payload" => %{"id" => "DLY-001"}
      }

      {:ok, result} = FlowExecutor.execute_sync(flow, input)
      execution = FlowExecutions.get_execution(result.execution_id)

      node_types =
        execution.node_executions
        |> Enum.filter(&(&1.status == "completed"))
        |> Enum.map(& &1.node_type)

      assert "delay" in node_types
    end

    test "3-way branching creates correct node execution records for order path", %{flow: flow} do
      input = %{"event_type" => "order.created", "payload" => %{"id" => "1"}}

      {:ok, result} = FlowExecutor.execute_sync(flow, input)
      execution = FlowExecutions.get_execution(result.execution_id)

      completed_types =
        execution.node_executions
        |> Enum.filter(&(&1.status == "completed"))
        |> Enum.map(& &1.node_type)
        |> MapSet.new()

      assert "start" in completed_types
      assert "debug" in completed_types
      assert "condition" in completed_types
      assert "delay" in completed_types
      assert "end" in completed_types
    end

    test "3-way branching: payment path executes payment node (n8)", %{flow: flow} do
      input = %{"event_type" => "payment.received", "payload" => %{"id" => "PAY-002"}}

      {:ok, result} = FlowExecutor.execute_sync(flow, input)
      execution = FlowExecutions.get_execution(result.execution_id)

      completed_ids =
        execution.node_executions
        |> Enum.filter(&(&1.status == "completed"))
        |> Enum.map(& &1.node_id)
        |> MapSet.new()

      # Payment path: n1(start), n2(debug), n3(validate), n4(condition), n8(payment), n9(end)
      assert "n8" in completed_ids
      assert "n9" in completed_ids
    end

    test "unknown event execution is recorded as failed in DB", %{flow: flow} do
      input = %{"event_type" => "subscription.cancelled"}

      {:error, error_info} = FlowExecutor.execute_sync(flow, input)
      execution = FlowExecutions.get_execution(error_info.execution_id)

      assert execution.status == "failed"
    end
  end

  # ── Cross-template node coverage ────────────────────────────

  describe "node type coverage across templates" do
    test "all 11 node types are exercised by at least one template" do
      all_types =
        ~w(start end elixir_code condition debug fail http_request delay for_each sub_flow webhook_wait)

      template_types =
        Templates.list()
        |> Enum.flat_map(fn t -> Enum.map(t.definition["nodes"], & &1["type"]) end)
        |> MapSet.new()

      for type <- all_types do
        assert type in template_types,
               "node type '#{type}' is not exercised by any template"
      end
    end

    test "LeadScoring definition contains debug and fail nodes" do
      definition = LeadScoring.definition()
      node_types = Enum.map(definition["nodes"], & &1["type"]) |> MapSet.new()

      assert "debug" in node_types
      assert "fail" in node_types
      assert "elixir_code" in node_types
      assert "condition" in node_types
    end

    test "WebhookProcessor definition contains delay, debug, and fail nodes" do
      definition = WebhookProcessor.definition()
      node_types = Enum.map(definition["nodes"], & &1["type"]) |> MapSet.new()

      assert "debug" in node_types
      assert "fail" in node_types
      assert "delay" in node_types
      assert "elixir_code" in node_types
      assert "condition" in node_types
    end

    test "LeadScoring elixir_code node has skip_condition configured" do
      definition = LeadScoring.definition()

      skip_nodes =
        Enum.filter(definition["nodes"], fn n ->
          n["type"] == "elixir_code" and n["data"]["skip_condition"]
        end)

      refute skip_nodes == []
    end

    test "WebhookProcessor elixir_code node has skip_condition configured" do
      definition = WebhookProcessor.definition()

      skip_nodes =
        Enum.filter(definition["nodes"], fn n ->
          n["type"] == "elixir_code" and n["data"]["skip_condition"]
        end)

      refute skip_nodes == []
    end
  end
end
