defmodule BlackboexWeb.FlowWebhookNewTemplatesTest do
  @moduledoc """
  E2E webhook tests for the 8 new flow templates:

    * stripe_payment_router
    * support_ticket_router
    * escalation_approval
    * data_enrichment_chain
    * incident_alert_pipeline
    * customer_onboarding
    * webhook_idempotent
    * abandoned_cart_recovery
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

  # ── Stripe Payment Router ───────────────────────────────────

  describe "POST /webhook/:token — stripe_payment_router" do
    setup do
      %{flow: create_active_flow("stripe_payment_router")}
    end

    test "payment.succeeded → fulfill_order", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "payment.succeeded",
          "payment_id" => "pi_001",
          "amount" => 4999,
          "customer_id" => "cus_001"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["status"] == "succeeded"
      assert output["action"] == "fulfill_order"
    end

    test "payment.failed → retry_payment path", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "payment.failed",
          "payment_id" => "pi_002",
          "amount" => 1000,
          "customer_id" => "cus_002"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["status"] == "failed"
      assert output["action"] == "retry_payment"
    end

    test "charge.disputed → create_case", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "charge.disputed",
          "payment_id" => "pi_003",
          "amount" => 5000,
          "customer_id" => "cus_003"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["status"] == "disputed"
      assert output["action"] == "create_case"
    end

    test "unknown event_type → fail node returns 422", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "refund.created",
          "payment_id" => "pi_004",
          "amount" => 1,
          "customer_id" => "cus_004"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Unknown payment event"
    end

    test "missing event_type → 422 schema validation", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "payment_id" => "pi_005",
          "amount" => 1,
          "customer_id" => "cus_005"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "event_type"
    end

    test "debug node stores event info in shared_state", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_type" => "payment.succeeded",
          "payment_id" => "pi_dbg",
          "amount" => 100,
          "customer_id" => "cus_dbg"
        })

      resp = json_response(conn, 200)
      exec = FlowExecutions.get_execution(resp["execution_id"])
      assert exec.shared_state["debug_event"]["payment_id"] == "pi_dbg"
    end
  end

  # ── Support Ticket Router ───────────────────────────────────

  describe "POST /webhook/:token — support_ticket_router" do
    setup do
      %{flow: create_active_flow("support_ticket_router")}
    end

    test "critical bug report → escalated", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "subject" => "App crash",
          "body" => "Error 500 in production",
          "sender_email" => "user@test.com",
          "urgency" => "critical"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["priority"] == "critical"
      assert output["category"] == "engineering"
      assert output["status"] == "escalated"
      assert output["assigned_team"] == "eng-team"
    end

    test "billing normal priority → queued", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "subject" => "Invoice question",
          "body" => "Wrong charge on my account",
          "sender_email" => "user@test.com",
          "urgency" => "normal"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["category"] == "billing"
      assert output["status"] == "queued"
    end

    test "low urgency general → backlog", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "subject" => "How to",
          "body" => "Question about features",
          "sender_email" => "user@test.com",
          "urgency" => "low"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["category"] == "general"
      assert output["priority"] == "low"
      assert output["status"] == "backlog"
    end

    test "auto-detect engineering from bug keyword", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "subject" => "Bug found",
          "body" => "crash on login",
          "sender_email" => "user@test.com"
        })

      resp = json_response(conn, 200)
      assert resp["output"]["category"] == "engineering"
    end

    test "missing subject → 422", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "body" => "test",
          "sender_email" => "u@test.com"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
      assert resp["error"] =~ "subject"
    end
  end

  # ── Escalation Approval ─────────────────────────────────────

  describe "POST /webhook/:token — escalation_approval" do
    setup do
      %{flow: create_active_flow("escalation_approval")}
    end

    test "below threshold → auto_approved", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "request" => "Office supplies",
          "amount" => 50,
          "requester" => "alice",
          "auto_approve_below" => 100
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["decision"] == "auto_approved"
      assert output["auto_approved"] == true
      assert output["approved_by"] == "system"
    end

    test "above threshold → halts on webhook_wait", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "request" => "New laptop",
          "amount" => 5000,
          "requester" => "bob",
          "auto_approve_below" => 100
        })

      resp = json_response(conn, 200)
      assert resp["status"] == "halted"
      assert resp["execution_id"]
    end

    test "no threshold → auto_approved (threshold 0)", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "request" => "Small thing",
          "amount" => 50,
          "requester" => "carol"
        })

      resp = json_response(conn, 200)
      assert resp["output"]["decision"] == "auto_approved"
    end

    test "missing request → 422", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "amount" => 100,
          "requester" => "dave"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
    end
  end

  # ── Data Enrichment Chain ───────────────────────────────────

  describe "POST /webhook/:token — data_enrichment_chain" do
    setup do
      %{flow: create_active_flow("data_enrichment_chain")}
    end

    @tag :external_http
    test "primary source found", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "email" => "alice@company.com"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["source"] == "primary"
      assert output["confidence"] == 90
      assert output["sources_tried"] == 1
    end

    @tag :external_http
    test "fallback source used when primary misses", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "email" => "fallback_user@company.com"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["source"] == "fallback"
      assert output["confidence"] == 60
      assert output["sources_tried"] == 2
    end

    test "missing email → 422", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{"name" => "Alice"})

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
    end
  end

  # ── Incident Alert Pipeline ─────────────────────────────────

  describe "POST /webhook/:token — incident_alert_pipeline" do
    setup do
      %{flow: create_active_flow("incident_alert_pipeline")}
    end

    @tag :external_http
    test "critical alert → ticket + notify", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "alert_name" => "DB Down",
          "severity" => "critical",
          "source" => "prometheus"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["severity_level"] == "critical"
      assert output["notification_sent"] == true
      assert output["ticket_id"] =~ "tkt_"
    end

    test "warning alert stays in warning branch", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "alert_name" => "High CPU",
          "severity" => "warning",
          "source" => "datadog"
        })

      resp = json_response(conn, 200)
      assert resp["output"]["severity_level"] == "warning"
    end

    test "info alert → info branch", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "alert_name" => "Deploy complete",
          "severity" => "info",
          "source" => "ci"
        })

      resp = json_response(conn, 200)
      assert resp["output"]["severity_level"] == "info"
    end

    test "duplicate alert skipped", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "alert_name" => "DB Down",
          "severity" => "critical",
          "source" => "prometheus",
          "fingerprint" => "dup_abc123"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["is_duplicate"] == true
    end

    test "debug stores alert info in shared_state", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "alert_name" => "Test",
          "severity" => "info",
          "source" => "test"
        })

      resp = json_response(conn, 200)
      exec = FlowExecutions.get_execution(resp["execution_id"])
      assert exec.shared_state["debug_alert"]["alert_name"] == "Test"
    end

    test "missing alert_name → 422", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "severity" => "info",
          "source" => "ci"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
    end
  end

  # ── Customer Onboarding ─────────────────────────────────────

  describe "POST /webhook/:token — customer_onboarding" do
    setup do
      %{flow: create_active_flow("customer_onboarding")}
    end

    test "enterprise customer completes onboarding", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "customer_name" => "Alice",
          "email" => "alice@co.com",
          "plan" => "enterprise"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["is_active"] == true
      assert output["onboarding_step"] == "completed"
      assert output["account_provisioned"] == true
      assert output["welcome_sent"] == true
    end

    test "inactive free customer gets nudge", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "customer_name" => "Bob",
          "email" => "bob@co.com",
          "plan" => "free"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["nudge_sent"] == true
      assert output["onboarding_step"] == "nudged"
      assert output["is_active"] == false
    end

    test "already_active flag short-circuits to active", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "customer_name" => "Carol",
          "email" => "c@co.com",
          "plan" => "free",
          "already_active" => true
        })

      resp = json_response(conn, 200)
      assert resp["output"]["is_active"] == true
    end

    test "missing customer_name → 422", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "email" => "x@test.com",
          "plan" => "free"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
    end
  end

  # ── Webhook Idempotent ──────────────────────────────────────

  describe "POST /webhook/:token — webhook_idempotent" do
    setup do
      %{flow: create_active_flow("webhook_idempotent")}
    end

    test "valid signature + new event → processed", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_id" => "evt_001",
          "event_type" => "order.created",
          "signature" => "valid_abc"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["signature_valid"] == true
      assert output["is_duplicate"] == false
      assert output["processing_result"] =~ "order.created"
      assert output["processed_at"] != ""
    end

    test "valid signature + duplicate → ack without processing", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_id" => "dup_001",
          "event_type" => "order.created",
          "signature" => "valid_abc"
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["is_duplicate"] == true
      assert output["signature_valid"] == true
    end

    test "invalid signature → fail 422", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_id" => "evt_002",
          "event_type" => "order.created",
          "signature" => "invalid_xyz"
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Invalid webhook signature"
    end

    test "no signature (nil) → treated as valid", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "event_id" => "evt_003",
          "event_type" => "test"
        })

      resp = json_response(conn, 200)
      assert resp["output"]["signature_valid"] == true
    end

    test "missing event_id → 422", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{"event_type" => "test"})

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
    end
  end

  # ── Abandoned Cart Recovery ─────────────────────────────────

  describe "POST /webhook/:token — abandoned_cart_recovery" do
    setup do
      %{flow: create_active_flow("abandoned_cart_recovery")}
    end

    test "large cart → 15% discount and full recovery sequence", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "customer_name" => "Alice",
          "customer_email" => "a@shop.com",
          "cart_total" => 15_000
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["discount_percent"] == 15
      assert output["reminder_sent"] == true
      assert output["final_offer_sent"] == true
      assert output["step"] == "final_offer"
    end

    test "already purchased → skip recovery", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "customer_name" => "Bob",
          "customer_email" => "b@shop.com",
          "cart_total" => 5000,
          "already_purchased" => true
        })

      resp = json_response(conn, 200)
      output = resp["output"]
      assert output["recovered"] == true
      assert output["step"] == "already_purchased"
    end

    test "medium cart → 10% discount", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "customer_name" => "Carol",
          "customer_email" => "c@shop.com",
          "cart_total" => 7500
        })

      resp = json_response(conn, 200)
      assert resp["output"]["discount_percent"] == 10
    end

    test "small cart → 5% discount", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "customer_name" => "Dave",
          "customer_email" => "d@shop.com",
          "cart_total" => 2000
        })

      resp = json_response(conn, 200)
      assert resp["output"]["discount_percent"] == 5
    end

    test "missing customer_name → 422", %{flow: flow} do
      conn =
        webhook_post(build_conn(), flow.webhook_token, %{
          "customer_email" => "x@shop.com",
          "cart_total" => 100
        })

      resp = json_response(conn, 422)
      assert resp["error"] =~ "Payload validation failed"
    end
  end
end
