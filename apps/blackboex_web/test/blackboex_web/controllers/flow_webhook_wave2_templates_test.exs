defmodule BlackboexWeb.FlowWebhookWave2TemplatesTest do
  @moduledoc """
  E2E webhook tests for the 8 Wave 2 flow templates:

    * llm_router
    * approval_with_timeout
    * saga_compensation
    * notification_fanout
    * sla_monitor
    * async_job_poller
    * github_ci_responder
    * sub_flow_orchestrator
  """

  use BlackboexWeb.ConnCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  alias Blackboex.FlowExecutions
  alias Blackboex.Flows

  # ── Helpers ─────────────────────────────────────────────────

  defp create_active_flow(template_id) do
    {user, org} = user_and_org_fixture()

    {:ok, flow} =
      Flows.create_flow_from_template(
        %{name: "Test #{template_id}", organization_id: org.id, user_id: user.id},
        template_id
      )

    {:ok, flow} = Flows.activate_flow(flow)
    flow
  end

  defp webhook_post(conn, token, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/webhook/#{token}", payload)
  end

  # ── LLM Router ──────────────────────────────────────────────

  describe "POST /webhook/:token — llm_router" do
    setup do
      %{flow: create_active_flow("llm_router")}
    end

    test "high budget + analysis → high tier model", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "prompt" => "Analyze this quarterly report for key insights",
          "task_type" => "analysis",
          "budget_tier" => "high"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["model_tier"] == "high"
      assert String.contains?(output["model_selected"], "opus")
      assert output["response"] != nil
      assert output["tokens_estimated"] > 0
    end

    test "standard generation → standard tier", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "prompt" => "Write a product description for a coffee mug",
          "task_type" => "generation",
          "budget_tier" => "standard"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["model_tier"] == "standard"
      assert String.contains?(output["model_selected"], "sonnet")
    end

    test "low budget + classification → low tier", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "prompt" => "Is this a complaint or a compliment?",
          "task_type" => "classification",
          "budget_tier" => "low"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["model_tier"] == "low"
      assert String.contains?(output["model_selected"], "haiku")
    end

    test "no budget_tier defaults to standard", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "prompt" => "Summarize this article",
          "task_type" => "summarization"
        })

      resp = json_response(conn, 200)
      assert resp["output"]["model_tier"] == "standard"
    end

    test "debug node stores routing info in shared_state", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "prompt" => "test prompt",
          "task_type" => "generation"
        })

      resp = json_response(conn, 200)
      exec = FlowExecutions.get_execution(resp["execution_id"])
      assert exec.shared_state["debug_routing"] != nil
    end

    test "missing prompt → 422 schema validation", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "task_type" => "generation"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "prompt"
    end
  end

  # ── Approval With Timeout ────────────────────────────────────

  describe "POST /webhook/:token — approval_with_timeout" do
    setup do
      %{flow: create_active_flow("approval_with_timeout")}
    end

    test "simulate_timeout=true → escalated immediately", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "request_title" => "Q4 Budget Increase",
          "requester" => "alice",
          "amount" => 50_000,
          "approver_email" => "manager@example.com",
          "simulate_timeout" => true
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["decision"] == "escalated"
      assert output["escalated"] == true
    end

    test "simulate_timeout=false → flow halts at webhook_wait", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "request_title" => "Hardware Purchase",
          "requester" => "bob",
          "amount" => 1_500,
          "approver_email" => "manager@example.com",
          "simulate_timeout" => false
        })

      resp = json_response(conn, 200)
      assert resp["status"] == "halted"
    end

    test "initial reminder_sent is false", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "request_title" => "Software License",
          "requester" => "carol",
          "amount" => 500,
          "approver_email" => "manager@example.com",
          "simulate_timeout" => true
        })

      resp = json_response(conn, 200)
      assert resp["output"]["reminder_sent"] == false
    end

    test "missing request_title → 422", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "requester" => "x",
          "amount" => 100,
          "approver_email" => "m@example.com"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "request_title"
    end
  end

  # ── Saga Compensation ────────────────────────────────────────

  describe "POST /webhook/:token — saga_compensation" do
    setup do
      %{flow: create_active_flow("saga_compensation")}
    end

    test "all steps succeed → saga_status=completed", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "order_id" => "ord_001",
          "customer_id" => "cus_001",
          "amount" => 9999,
          "items" => [%{"sku" => "WIDGET-1", "qty" => 2}]
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["saga_status"] == "completed"
      assert output["inventory_reserved"] == true
      assert output["payment_charged"] == true
      assert output["shipment_created"] == true
    end

    test "fail at inventory → 422, compensation_ran=false", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "order_id" => "ord_002",
          "customer_id" => "cus_002",
          "amount" => 1000,
          "items" => [],
          "simulate_failure_at" => "inventory"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Inventory"
    end

    test "fail at payment → 422, compensation_ran=true", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "order_id" => "ord_003",
          "customer_id" => "cus_003",
          "amount" => 5000,
          "items" => [%{"sku" => "THING-1", "qty" => 1}],
          "simulate_failure_at" => "payment"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payment"
    end

    test "fail at shipment → 422, full compensation ran", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "order_id" => "ord_004",
          "customer_id" => "cus_004",
          "amount" => 2000,
          "items" => [%{"sku" => "GADGET-1", "qty" => 1}],
          "simulate_failure_at" => "shipment"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Shipment"

      exec = FlowExecutions.get_execution(resp["execution_id"])
      assert exec.shared_state["compensation_ran"] == true
      assert exec.shared_state["payment_charged"] == false
    end

    test "missing order_id → 422 schema validation", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "customer_id" => "cus_x",
          "amount" => 100,
          "items" => []
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "order_id"
    end
  end

  # ── Notification Fanout ──────────────────────────────────────

  describe "POST /webhook/:token — notification_fanout" do
    setup do
      %{flow: create_active_flow("notification_fanout")}
    end

    test "critical severity → 3 channels notified", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "alert",
          "title" => "Database Down",
          "message" => "Primary DB unreachable",
          "severity" => "critical"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["notifications_sent"] == 3
      assert length(output["channels"]) == 3
    end

    test "high severity → 2 channels", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "alert",
          "title" => "High CPU",
          "message" => "CPU at 95%",
          "severity" => "high"
        })

      resp = json_response(conn, 200)
      assert resp["output"]["notifications_sent"] == 2
    end

    test "medium severity → 1 channel", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "deploy",
          "title" => "Deploy complete",
          "message" => "v1.2.3 deployed",
          "severity" => "medium"
        })

      resp = json_response(conn, 200)
      assert resp["output"]["notifications_sent"] == 1
    end

    test "for_each results tracked with status=sent", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "alert",
          "title" => "Critical Alert",
          "message" => "System down",
          "severity" => "critical"
        })

      resp = json_response(conn, 200)
      results = resp["output"]["results"]
      assert length(results) == 3
      assert Enum.all?(results, fn r -> r["status"] == "sent" end)
    end

    test "debug node stores event info in shared_state", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "announcement",
          "title" => "Test",
          "message" => "Test message",
          "severity" => "low"
        })

      resp = json_response(conn, 200)
      exec = FlowExecutions.get_execution(resp["execution_id"])
      assert exec.shared_state["debug_event"] != nil
    end

    test "missing severity → 422 schema validation", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "deploy",
          "title" => "Test",
          "message" => "msg"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "severity"
    end
  end

  # ── SLA Monitor ──────────────────────────────────────────────

  describe "POST /webhook/:token — sla_monitor" do
    setup do
      %{flow: create_active_flow("sla_monitor")}
    end

    test "critical ticket breached → breached_count=1", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "tickets" => [
            %{
              "id" => "T1",
              "priority" => "critical",
              "age_hours" => 3,
              "title" => "DB down",
              "assignee" => "ops-team"
            }
          ]
        })

      resp = json_response(conn, 200)
      assert resp["output"]["breached_count"] == 1
    end

    test "no breach → breached_count=0, all_clear path", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "tickets" => [
            %{
              "id" => "T1",
              "priority" => "normal",
              "age_hours" => 1,
              "title" => "Question",
              "assignee" => "support"
            }
          ]
        })

      resp = json_response(conn, 200)
      assert resp["output"]["breached_count"] == 0
    end

    test "mixed tickets → correct breach count", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "tickets" => [
            %{
              "id" => "T1",
              "priority" => "critical",
              "age_hours" => 5,
              "title" => "Critical",
              "assignee" => "ops"
            },
            %{
              "id" => "T2",
              "priority" => "normal",
              "age_hours" => 2,
              "title" => "Normal",
              "assignee" => "support"
            }
          ]
        })

      resp = json_response(conn, 200)
      assert resp["output"]["breached_count"] == 1
    end

    test "empty tickets list → total_tickets=0, breached_count=0", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{"tickets" => []})

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["total_tickets"] == 0
      assert output["breached_count"] == 0
    end

    test "report_generated_at is set", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "tickets" => [
            %{
              "id" => "T1",
              "priority" => "high",
              "age_hours" => 1,
              "title" => "T",
              "assignee" => "x"
            }
          ]
        })

      resp = json_response(conn, 200)
      assert resp["output"]["report_generated_at"] != nil
      assert resp["output"]["report_generated_at"] != ""
    end

    test "missing tickets → 422 schema validation", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "sla_thresholds" => %{"critical" => 1}
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "tickets"
    end
  end

  # ── Async Job Poller ─────────────────────────────────────────

  describe "POST /webhook/:token — async_job_poller" do
    setup do
      %{flow: create_active_flow("async_job_poller")}
    end

    test "complete_immediately → completed after 1 poll", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "job_type" => "transcoding",
          "input_url" => "https://example.com/video.mp4",
          "simulate_job_id" => "complete_immediately"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["job_status"] == "completed"
      assert output["poll_count"] == 1
      assert output["result_url"] != nil
    end

    test "normal job completes on second poll", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "job_type" => "ml_inference",
          "input_url" => "https://example.com/data.json"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["job_status"] == "completed"
      assert output["poll_count"] == 2
    end

    test "fail_on_poll → 422 error", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "job_type" => "report",
          "input_url" => "https://example.com/input.csv",
          "simulate_job_id" => "fail_on_poll"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "failed"
    end

    test "job_id is recorded in shared_state", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "job_type" => "transcoding",
          "input_url" => "https://example.com/vid.mp4",
          "simulate_job_id" => "complete_immediately"
        })

      resp = json_response(conn, 200)
      exec = FlowExecutions.get_execution(resp["execution_id"])
      assert exec.shared_state["job_id"] == "complete_immediately"
    end

    test "poll_count is tracked", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "job_type" => "transcoding",
          "input_url" => "https://example.com/vid.mp4",
          "simulate_job_id" => "complete_immediately"
        })

      resp = json_response(conn, 200)
      assert resp["output"]["poll_count"] >= 1
    end

    test "missing input_url → 422 schema validation", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "job_type" => "transcoding"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "input_url"
    end
  end

  # ── GitHub CI Responder ──────────────────────────────────────

  describe "POST /webhook/:token — github_ci_responder" do
    setup do
      %{flow: create_active_flow("github_ci_responder")}
    end

    test "build_failed → ticket_created", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "build_failed",
          "repository" => "myorg/api",
          "branch" => "main",
          "actor" => "github-actions",
          "build_url" => "https://ci.example.com/builds/123"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["action_taken"] == "ticket_created"
      assert output["notification_sent"] == true
    end

    test "pr_merged → merge_notified", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "pr_merged",
          "repository" => "myorg/api",
          "branch" => "feature/auth",
          "actor" => "john",
          "pr_number" => 42
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["action_taken"] == "merge_notified"
      assert output["notification_sent"] == true
    end

    test "deployment_success → deploy_triggered", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "deployment_success",
          "repository" => "myorg/api",
          "branch" => "main",
          "actor" => "github-actions"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["action_taken"] == "deploy_triggered"
      assert output["deploy_triggered"] == true
    end

    test "pr_opened → pr_acknowledged", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "pr_opened",
          "repository" => "myorg/api",
          "branch" => "feature/new-ui",
          "actor" => "jane",
          "pr_number" => 43
        })

      resp = json_response(conn, 200)
      assert resp["output"]["action_taken"] == "pr_acknowledged"
    end

    test "debug node stores event info in shared_state", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "build_failed",
          "repository" => "myorg/api",
          "branch" => "main",
          "actor" => "ci"
        })

      resp = json_response(conn, 200)
      exec = FlowExecutions.get_execution(resp["execution_id"])
      assert exec.shared_state["debug_event"] != nil
    end

    test "missing repository → 422 schema validation", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "build_failed",
          "branch" => "main",
          "actor" => "ci"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "repository"
    end
  end

  # ── Sub-flow Orchestrator ────────────────────────────────────

  describe "POST /webhook/:token — sub_flow_orchestrator" do
    setup do
      %{flow: create_active_flow("sub_flow_orchestrator")}
    end

    test "valid order with items → order_status=confirmed", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "order_id" => "ord_001",
          "customer_id" => "cus_001",
          "items" => [%{"sku" => "WIDGET-1", "qty" => 2}],
          "total_amount" => 5999
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["order_status"] == "confirmed"
      assert output["payment_valid"] == true
      assert output["inventory_available"] == true
    end

    test "empty items → inventory_hold", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "order_id" => "ord_002",
          "customer_id" => "cus_002",
          "items" => [],
          "total_amount" => 1000
        })

      resp = json_response(conn, 200)
      assert resp["output"]["order_status"] == "inventory_hold"
    end

    test "total_amount=0 → payment_failed", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "order_id" => "ord_003",
          "customer_id" => "cus_003",
          "items" => [%{"sku" => "X", "qty" => 1}],
          "total_amount" => 0
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payment validation failed"
      assert resp["error"] =~ "ord_003"
    end

    test "payment_result and inventory_result are maps in output", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "order_id" => "ord_004",
          "customer_id" => "cus_004",
          "items" => [%{"sku" => "A", "qty" => 1}],
          "total_amount" => 999
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert is_map(output["payment_result"])
      assert is_map(output["inventory_result"])
      assert output["payment_result"]["simulated"] == true
    end

    test "missing order_id → 422 schema validation", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "customer_id" => "cus_x",
          "items" => [],
          "total_amount" => 100
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "order_id"
    end
  end
end
