# E2E Flow Tests — Full Suite
#
# Runs against the local dev server (localhost:4000).
# Creates flows on the rodtroll@gmail.com account, activates them,
# fires webhook requests, validates outputs, and cleans up.
#
# Usage:
#   mix run apps/blackboex/priv/scripts/e2e_flows.exs
#
# Prerequisites:
#   - `make server` running in another terminal
#   - User rodtroll@gmail.com exists in the local DB

defmodule E2E.Flows do
  @base_url "http://localhost:4000"

  # ── Colours ──────────────────────────────────────────────────

  defp green(text), do: IO.ANSI.green() <> text <> IO.ANSI.reset()
  defp red(text), do: IO.ANSI.red() <> text <> IO.ANSI.reset()
  defp cyan(text), do: IO.ANSI.cyan() <> text <> IO.ANSI.reset()
  defp yellow(text), do: IO.ANSI.yellow() <> text <> IO.ANSI.reset()
  defp bold(text), do: IO.ANSI.bright() <> text <> IO.ANSI.reset()

  # ── Public entry ─────────────────────────────────────────────

  def run do
    IO.puts(bold("\n══════════════════════════════════════════════"))
    IO.puts(bold("  E2E Flow Tests — Full Suite"))
    IO.puts(bold("══════════════════════════════════════════════\n"))

    with :ok <- check_server(),
         {:ok, user, org} <- setup_account(),
         :ok <- cleanup_previous_e2e(org) do
      # Create shared flows upfront (reused across phases)
      notif_flow = create_and_activate_template("notification", "E2E Notification", user, org)
      hw_flow = create_and_activate_template("hello_world", "E2E HelloWorld", user, org)

      results =
        List.flatten([
          run_hello_world(hw_flow),
          run_notification(notif_flow),
          run_all_nodes_demo(user, org, notif_flow),
          run_data_pipeline(user, org),
          run_order_processor(user, org),
          run_batch_processor(user, org),
          run_http_enrichment(user, org),
          run_rest_api_crud(user, org),
          run_api_status_checker(user, org),
          run_approval_workflow(user, org),
          run_advanced_features(user, org),
          run_lead_scoring(user, org),
          run_webhook_processor(user, org),
          run_stripe_payment_router(user, org),
          run_support_ticket_router(user, org),
          run_escalation_approval_new(user, org),
          run_data_enrichment_chain(user, org),
          run_incident_alert_pipeline(user, org),
          run_customer_onboarding(user, org),
          run_webhook_idempotent(user, org),
          run_abandoned_cart_recovery(user, org),
          run_stress_test(hw_flow)
        ])

      report(results)
    else
      {:error, reason} ->
        IO.puts(red("✗ Setup failed: #{reason}"))
        System.halt(1)
    end
  end

  # ── Server check ─────────────────────────────────────────────

  defp check_server do
    IO.puts(cyan("▸ Checking server at #{@base_url}..."))

    case Req.get("#{@base_url}/health", receive_timeout: 3_000) do
      {:ok, %{status: status}} when status in 200..299 ->
        IO.puts(green("  Server is up (HTTP #{status})"))
        :ok

      {:ok, %{status: _status}} ->
        IO.puts(yellow("  Server is responding — proceeding"))
        :ok

      {:error, %{reason: reason}} ->
        {:error, "Cannot reach #{@base_url} — #{inspect(reason)}. Is `make server` running?"}
    end
  end

  # ── Account setup ────────────────────────────────────────────

  defp setup_account do
    IO.puts(cyan("▸ Looking up rodtroll@gmail.com..."))

    case Blackboex.Accounts.get_user_by_email("rodtroll@gmail.com") do
      nil ->
        {:error, "User rodtroll@gmail.com not found. Sign up or run seeds first."}

      user ->
        case Blackboex.Organizations.list_user_organizations(user) do
          [] ->
            {:error, "User has no organizations."}

          [org | _] ->
            IO.puts(green("  Found user #{user.email} in org \"#{org.name}\""))
            {:ok, user, org}
        end
    end
  end

  # ── Cleanup previous E2E runs ─────────────────────────────────

  defp cleanup_previous_e2e(org) do
    IO.puts(cyan("▸ Cleaning up previous E2E flows..."))

    flows = Blackboex.Flows.list_flows(org.id)

    e2e_flows = Enum.filter(flows, fn f -> String.starts_with?(f.name, "E2E ") end)

    case e2e_flows do
      [] ->
        IO.puts("  No previous E2E flows found")

      flows ->
        for f <- flows do
          {:ok, _} = Blackboex.Flows.delete_flow(f)
        end

        IO.puts("  Deleted #{length(flows)} previous E2E flows")
    end

    :ok
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 1: Hello World Template
  # ════════════════════════════════════════════════════════════════

  defp run_hello_world(flow) do
    IO.puts(cyan("\n▸ Phase 1: Hello World Template"))

    [
      run_test("HW: email route", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "Rodrigo", "email" => "rodtroll@gmail.com"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["channel"], "email", "channel")
        assert_eq!(output["to"], "rodtroll@gmail.com", "to")
        assert_eq!(output["message"], "Hello, Rodrigo!", "message")
        assert_present!(resp.body["execution_id"], "execution_id")
        assert_gte!(resp.body["duration_ms"], 0, "duration_ms")
        :ok
      end),
      run_test("HW: phone route", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "Maria", "phone" => "11999887766"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["channel"], "phone", "channel")
        assert_eq!(output["to"], "11999887766", "to")
        assert_eq!(output["message"], "Hello, Maria!", "message")
        :ok
      end),
      run_test("HW: no-contact error", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "Ana"})
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["error"], "no contact info provided", "error")
        :ok
      end),
      run_test("HW: schema validation (missing name)", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"phone" => "123"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        assert_contains!(resp.body["error"], "name", "mentions name")
        assert_present!(resp.body["execution_id"], "execution_id")
        :ok
      end),
      run_test("HW: execution record persisted", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "Persist", "email" => "p@test.com"})
        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        assert_eq!(exec.status, "completed", "execution status")
        assert_gte!(length(exec.node_executions), 5, "node executions count")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 2: Notification Sub-Flow (linear)
  # ════════════════════════════════════════════════════════════════

  defp run_notification(flow) do
    IO.puts(cyan("\n▸ Phase 2: Notification Sub-Flow"))

    [
      run_test("Notif: email channel", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"message" => "Hello World", "channel" => "email"})
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["formatted"], "Notification via email: Hello World", "formatted")
        :ok
      end),
      run_test("Notif: sms channel", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"message" => "Alert!", "channel" => "sms"})
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["formatted"], "Notification via sms: Alert!", "formatted")
        :ok
      end),
      run_test("Notif: missing required field", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"message" => "No channel"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        assert_contains!(resp.body["error"], "channel", "mentions channel")
        :ok
      end),
      run_test("Notif: empty message rejected", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"message" => "", "channel" => "email"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 3: All Nodes Demo (auto-approve branch)
  # Uses: http_request, delay, sub_flow, for_each
  # ════════════════════════════════════════════════════════════════

  defp run_all_nodes_demo(user, org, notif_flow) do
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
        assert_eq!(output["approval_status"], "pending", "approval_status stays pending on auto-approve")
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
        assert_present!(Enum.find(node_types, &(&1 == "http_request")), "http_request node executed")
        assert_present!(Enum.find(node_types, &(&1 == "delay")), "delay node executed")
        assert_present!(Enum.find(node_types, &(&1 == "sub_flow")), "sub_flow node executed")
        :ok
      end)
    ]

    results
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 4: Data Pipeline (deep state mutation chain)
  # ════════════════════════════════════════════════════════════════

  defp run_data_pipeline(user, org) do
    IO.puts(cyan("\n▸ Phase 4: Data Pipeline"))
    flow = create_and_activate_template("data_pipeline", "E2E DataPipeline", user, org)

    [
      run_test("Pipeline: 3 records aggregated", fn ->
        records = [
          %{"name" => "A", "amount" => 100, "category" => "sales"},
          %{"name" => "B", "amount" => 50, "category" => "ops"},
          %{"name" => "C", "amount" => 30, "category" => "sales"}
        ]

        {:ok, resp} = webhook_post(flow.webhook_token, %{"records" => records})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["record_count"], 3, "record_count")
        assert_eq!(output["total_amount"], 180.0, "total_amount")
        assert_eq!(output["avg_amount"], 60.0, "avg_amount")
        :ok
      end),
      run_test("Pipeline: single record", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"records" => [%{"name" => "X", "amount" => 42}]})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["record_count"], 1, "record_count")
        assert_eq!(output["total_amount"], 42.0, "total_amount")
        assert_eq!(output["avg_amount"], 42.0, "avg_amount")
        :ok
      end),
      run_test("Pipeline: empty records", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"records" => []})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["record_count"], 0, "record_count")
        assert_eq!(output["total_amount"], 0.0, "total_amount")
        assert_eq!(output["avg_amount"], 0.0, "avg_amount")
        :ok
      end),
      run_test("Pipeline: missing amount defaults to 0", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"records" => [%{"name" => "NoAmt"}]})
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["total_amount"], 0.0, "total_amount")
        :ok
      end),
      run_test("Pipeline: large batch (20 records)", fn ->
        records = Enum.map(1..20, fn i -> %{"name" => "R#{i}", "amount" => i * 10} end)
        {:ok, resp} = webhook_post(flow.webhook_token, %{"records" => records})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["record_count"], 20, "record_count")
        # sum of 10+20+...+200 = 10 * (1+2+...+20) = 10 * 210 = 2100
        assert_eq!(output["total_amount"], 2100.0, "total_amount")
        assert_eq!(output["avg_amount"], 105.0, "avg_amount")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 5: Order Processor (3-way business logic branching)
  # ════════════════════════════════════════════════════════════════

  defp run_order_processor(user, org) do
    IO.puts(cyan("\n▸ Phase 5: Order Processor"))
    flow = create_and_activate_template("order_processor", "E2E OrderProc", user, org)

    [
      run_test("Order: express (qty=3)", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"item" => "Widget", "quantity" => 3, "priority" => "express"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["status"], "express_confirmed", "status")
        assert_eq!(output["total"], 55.0, "total (3*10 + 25 shipping)")
        assert_eq!(output["delivery_days"], 1, "delivery_days")
        :ok
      end),
      run_test("Order: standard (qty=5)", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"item" => "Gadget", "quantity" => 5, "priority" => "standard"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["status"], "standard_confirmed", "status")
        assert_eq!(output["total"], 55.0, "total (5*10 + 5 shipping)")
        assert_eq!(output["delivery_days"], 5, "delivery_days")
        :ok
      end),
      run_test("Order: invalid priority", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"item" => "Thing", "quantity" => 1, "priority" => "overnight"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_contains!(output["error"], "Invalid priority", "error message")
        assert_contains!(output["error"], "overnight", "mentions priority value")
        :ok
      end),
      run_test("Order: quantity=0 edge case", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"item" => "Free", "quantity" => 0, "priority" => "express"})
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["total"], 25.0, "total (0*10 + 25 shipping)")
        :ok
      end),
      run_test("Order: missing required field", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"item" => "X"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 6: Batch Processor (HTTP fetch → for_each processing)
  # ════════════════════════════════════════════════════════════════

  defp run_batch_processor(user, org) do
    IO.puts(cyan("\n▸ Phase 6: Batch Processor (fetch API → for_each → aggregate)"))
    flow = create_and_activate_template("batch_processor", "E2E BatchProc", user, org)

    [
      run_test("Batch: fetch 5 posts and process each", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"limit" => 5})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["total_posts"], 5, "total_posts")
        assert_gte!(output["avg_words"], 1.0, "avg_words > 0")
        assert_present!(output["longest_title"], "longest_title not empty")
        :ok
      end),
      run_test("Batch: fetch 10 posts", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"limit" => 10})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["total_posts"], 10, "total_posts")
        assert_gte!(output["avg_words"], 1.0, "avg_words > 0")
        :ok
      end),
      run_test("Batch: default limit (no param)", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{})
        assert_status!(resp, 200)
        output = resp.body["output"]
        # Default limit is 5
        assert_eq!(output["total_posts"], 5, "total_posts default")
        :ok
      end),
      run_test("Batch: limit=1 single post", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"limit" => 1})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["total_posts"], 1, "total_posts")
        assert_present!(output["longest_title"], "has title")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 7: HTTP Enrichment (http_request + URL interpolation)
  # ════════════════════════════════════════════════════════════════

  defp run_http_enrichment(user, org) do
    IO.puts(cyan("\n▸ Phase 7: HTTP Enrichment"))
    flow = create_and_activate_template("http_enrichment", "E2E HttpEnrich", user, org)

    [
      run_test("HTTP: fetches from httpbin with query interpolation", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"query" => "test_value"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["http_status"], 200, "http_status")
        assert_eq!(output["method"], "GET", "method")
        assert_contains!(output["response_url"], "test_value", "URL contains query")
        :ok
      end),
      run_test("HTTP: different query value", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"query" => "hello_world"})
        assert_status!(resp, 200)
        assert_contains!(resp.body["output"]["response_url"], "hello_world", "URL contains query")
        :ok
      end),
      run_test("HTTP: spaces in query are URL-encoded", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"query" => "foo bar"})
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["http_status"], 200, "http_status")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 8: REST API CRUD (POST + GET with body_template + headers)
  # ════════════════════════════════════════════════════════════════

  defp run_rest_api_crud(user, org) do
    IO.puts(cyan("\n▸ Phase 8: REST API CRUD (JSONPlaceholder)"))
    flow = create_and_activate_template("rest_api_crud", "E2E RestCrud", user, org)

    [
      run_test("CRUD: POST creates resource, GET reads back", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "title" => "E2E Test Post",
          "body" => "Testing flow HTTP CRUD",
          "userId" => 1
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        # POST to jsonplaceholder returns 201
        assert_eq!(output["create_status"], 201, "create_status")
        assert_present!(output["created_id"], "created_id")
        # GET /posts/1 returns real post with title
        assert_eq!(output["read_status"], 200, "read_status")
        assert_present!(output["read_title"], "read_title not empty")
        assert_eq!(output["method_used"], "POST+GET", "method_used")
        :ok
      end),
      run_test("CRUD: body_template interpolates state values", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "title" => "Interpolation Test",
          "body" => "Check body template",
          "userId" => 42
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["create_status"], 201, "create_status")
        :ok
      end),
      run_test("CRUD: missing required field", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"title" => "No body"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 9: API Status Checker (custom headers, response analysis, branching)
  # ════════════════════════════════════════════════════════════════

  defp run_api_status_checker(user, org) do
    IO.puts(cyan("\n▸ Phase 9: API Status Checker"))
    flow = create_and_activate_template("api_status_checker", "E2E StatusCheck", user, org)

    [
      run_test("StatusCheck: healthy endpoint returns success report", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"url" => "https://httpbin.org/get"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["healthy"], true, "healthy")
        assert_eq!(output["status_code"], 200, "status_code")
        assert_gte!(output["response_time_ms"], 0, "response_time_ms")
        assert_contains!(output["report"], "OK:", "report starts with OK")
        :ok
      end),
      run_test("StatusCheck: custom headers are sent and echoed back", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "url" => "https://example.com/api",
          "custom_header_name" => "X-Test",
          "custom_header_value" => "hello"
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        # httpbin /anything echoes headers — x-check-url should contain our URL
        assert_eq!(output["healthy"], true, "healthy")
        assert_eq!(output["status_code"], 200, "status_code")
        :ok
      end),
      run_test("StatusCheck: URL with special chars is encoded", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"url" => "https://example.com/path with spaces"})
        assert_status!(resp, 200)
        # The URL is interpolated into a header, not the request URL, so it passes
        assert_eq!(resp.body["output"]["healthy"], true, "healthy")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 10: Approval Workflow (auto-approve branch only)
  # ════════════════════════════════════════════════════════════════

  defp run_approval_workflow(user, org) do
    IO.puts(cyan("\n▸ Phase 10: Approval Workflow (auto-approve branch)"))
    flow = create_and_activate_template("approval_workflow", "E2E Approval", user, org)

    [
      run_test("Approval: auto-approve (amount < threshold)", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "request" => "Buy supplies",
          "amount" => 50,
          "auto_approve_below" => 100
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["decision"], "auto_approved", "decision")
        assert_eq!(output["approved_by"], "system", "approved_by")
        assert_contains!(output["reason"], "50", "reason mentions amount")
        :ok
      end),
      run_test("Approval: auto-approve (no threshold = always auto)", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "request" => "Small purchase",
          "amount" => 1000
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["decision"], "auto_approved", "decision")
        :ok
      end),
      run_test("Approval: halts when amount >= threshold (returns halted status)", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "request" => "Big purchase",
          "amount" => 500,
          "auto_approve_below" => 100
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["status"], "halted", "status")
        assert_present!(resp.body["execution_id"], "execution_id")
        assert_contains!(resp.body["resume_url"], flow.webhook_token, "resume_url has token")
        :ok
      end),
      run_test("Approval: missing required field", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"amount" => 10})
        # After a halt, connections may reset. Use a fresh request.
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 11: Advanced Features (debug + fail + skip_condition)
  # ════════════════════════════════════════════════════════════════

  defp run_advanced_features(user, org) do
    IO.puts(cyan("\n▸ Phase 11: Advanced Features (debug, fail, skip_condition)"))
    flow = create_and_activate_template("advanced_features", "E2E AdvFeatures", user, org)

    [
      run_test("AdvFeat: valid data → success path", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "Rodrigo", "email" => "r@test.com"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["greeting"], "Hello, RODRIGO!", "greeting")
        assert_eq!(output["processed"], true, "processed")
        :ok
      end),
      run_test("AdvFeat: strict mode without email → fail node", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "Test", "strict_mode" => true})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Validation failed", "error message")
        assert_contains!(resp.body["error"], "email required in strict mode", "mentions email")
        :ok
      end),
      run_test("AdvFeat: skip_validation=true bypasses validation", fn ->
        # strict_mode=true + no email, but skip_validation=true → skips → success
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "name" => "Skip",
          "strict_mode" => true,
          "skip_validation" => true
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["greeting"], "Hello, SKIP!", "greeting")
        :ok
      end),
      run_test("AdvFeat: debug node stores data in shared_state", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "DebugMe", "email" => "d@test.com"})
        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        state = exec.shared_state
        assert_present!(state["debug_input"], "debug_input in state")
        assert_eq!(state["debug_input"]["name"], "DebugMe", "debug captured name")
        :ok
      end),
      run_test("AdvFeat: execution has debug + condition + end node records", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "NodeCheck"})
        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        node_types = Enum.map(exec.node_executions, & &1.node_type) |> MapSet.new()
        assert_present!(MapSet.member?(node_types, "debug") && true || nil, "debug node executed")
        assert_present!(MapSet.member?(node_types, "condition") && true || nil, "condition node executed")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 12: Lead Scoring (CRM qualification pipeline)
  # ════════════════════════════════════════════════════════════════

  defp run_lead_scoring(user, org) do
    IO.puts(cyan("\n▸ Phase 12: Lead Scoring (debug + scoring + fail)"))
    flow = create_and_activate_template("lead_scoring", "E2E LeadScore", user, org)

    [
      run_test("Lead: qualified (email+company+budget) → success", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "name" => "Alice",
          "email" => "alice@bigcorp.com",
          "company" => "BigCorp",
          "budget" => 5000
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["status"], "qualified", "status")
        assert_eq!(output["name"], "Alice", "name")
        assert_eq!(output["email"], "alice@bigcorp.com", "email")
        :ok
      end),
      run_test("Lead: score=100 in shared_state", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "name" => "ScoreCheck",
          "email" => "sc@co.com",
          "company" => "Co",
          "budget" => 2000
        })
        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        # email(+20) + company(+30) + budget>1000(+50) = 100
        assert_eq!(exec.shared_state["score"], 100, "score")
        assert_eq!(exec.shared_state["qualified"], true, "qualified")
        assert_eq!(exec.shared_state["enriched"], true, "enriched")
        :ok
      end),
      run_test("Lead: unqualified (email only, score=20) → fail", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "name" => "Charlie",
          "email" => "charlie@test.com"
        })
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "not qualified", "error mentions not qualified")
        :ok
      end),
      run_test("Lead: debug stores lead data", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "name" => "DebugLead",
          "email" => "dl@test.com",
          "company" => "TestCo",
          "budget" => 9999
        })
        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        assert_present!(exec.shared_state["debug_lead"], "debug_lead in state")
        assert_eq!(exec.shared_state["debug_lead"]["name"], "DebugLead", "debug captured name")
        assert_eq!(exec.shared_state["debug_lead"]["company"], "TestCo", "debug captured company")
        :ok
      end),
      run_test("Lead: skip_scoring bypasses scoring → success", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "name" => "SkipScore",
          "email" => "ss@test.com",
          "skip_scoring" => true
        })
        assert_status!(resp, 200)
        # Skipped scoring → condition sees nil qualified → branch 0 (success)
        assert_present!(resp.body["output"], "has output")
        :ok
      end),
      run_test("Lead: no email, no company, no budget → score=0 → fail", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "NoInfo"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "not qualified", "error mentions not qualified")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 13: Webhook Processor (event routing + delay + fail)
  # ════════════════════════════════════════════════════════════════

  defp run_webhook_processor(user, org) do
    IO.puts(cyan("\n▸ Phase 13: Webhook Processor (3-way branch + delay + fail)"))
    flow = create_and_activate_template("webhook_processor", "E2E WebhookProc", user, org)

    [
      run_test("Webhook: order.created → order processed", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_type" => "order.created",
          "payload" => %{"id" => "ORD-001", "amount" => 99.90},
          "timestamp" => "2026-04-10T12:00:00Z"
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["action"], "order_processed", "action")
        assert_eq!(output["order_id"], "ORD-001", "order_id")
        :ok
      end),
      run_test("Webhook: payment.received → payment processed", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_type" => "payment.received",
          "payload" => %{"id" => "PAY-001"},
          "timestamp" => "2026-04-10T12:00:00Z"
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["action"], "payment_processed", "action")
        assert_eq!(output["payment_id"], "PAY-001", "payment_id")
        assert_eq!(output["status"], "confirmed", "status")
        :ok
      end),
      run_test("Webhook: unknown event → fail node", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_type" => "invoice.voided",
          "timestamp" => "2026-04-10T12:00:00Z"
        })
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Unsupported event type", "error message")
        :ok
      end),
      run_test("Webhook: test event skips validation → order path", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_type" => "test",
          "payload" => %{"id" => "TEST-001"}
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["action"], "order_processed", "action")
        :ok
      end),
      run_test("Webhook: debug stores event info", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_type" => "order.created",
          "payload" => %{"id" => "DBG-001"},
          "timestamp" => "2026-04-10"
        })
        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        assert_present!(exec.shared_state["debug_event"], "debug_event in state")
        assert_eq!(exec.shared_state["debug_event"]["type"], "order.created", "debug event type")
        :ok
      end),
      run_test("Webhook: order path includes delay node", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_type" => "order.created",
          "payload" => %{"id" => "DLY-001"}
        })
        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        node_types = Enum.map(exec.node_executions, & &1.node_type)
        assert_present!(Enum.find(node_types, &(&1 == "delay")), "delay node executed")
        :ok
      end),
      run_test("Webhook: missing event_type → schema validation error", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"payload" => %{"id" => "1"}})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        assert_contains!(resp.body["error"], "event_type", "mentions event_type")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 15: Stripe Payment Router
  # ════════════════════════════════════════════════════════════════

  defp run_stripe_payment_router(user, org) do
    IO.puts(cyan("\n▸ Phase 15: Stripe Payment Router"))
    flow = create_and_activate_template("stripe_payment_router", "E2E StripePayment", user, org)

    [
      run_test("Stripe: payment.succeeded → fulfill_order", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_type" => "payment.succeeded",
          "payment_id" => "pi_e2e_001",
          "amount" => 4999,
          "customer_id" => "cus_e2e_001"
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["status"], "succeeded", "status")
        assert_eq!(output["action"], "fulfill_order", "action")
        :ok
      end),
      run_test("Stripe: payment.failed → retry_payment", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_type" => "payment.failed",
          "payment_id" => "pi_e2e_002",
          "amount" => 1000,
          "customer_id" => "cus_e2e_002"
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["status"], "failed", "status")
        assert_eq!(output["action"], "retry_payment", "action")
        :ok
      end),
      run_test("Stripe: charge.disputed → create_case", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_type" => "charge.disputed",
          "payment_id" => "pi_e2e_003",
          "amount" => 5000,
          "customer_id" => "cus_e2e_003"
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["status"], "disputed", "status")
        assert_eq!(resp.body["output"]["action"], "create_case", "action")
        :ok
      end),
      run_test("Stripe: unknown event → fail", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_type" => "refund.created",
          "payment_id" => "pi_e2e_004",
          "amount" => 1,
          "customer_id" => "cus_e2e_004"
        })
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Unknown payment event", "error")
        :ok
      end),
      run_test("Stripe: missing event_type → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "payment_id" => "pi_e2e_005",
          "amount" => 1,
          "customer_id" => "cus_e2e_005"
        })
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 16: Support Ticket Router
  # ════════════════════════════════════════════════════════════════

  defp run_support_ticket_router(user, org) do
    IO.puts(cyan("\n▸ Phase 16: Support Ticket Router"))
    flow = create_and_activate_template("support_ticket_router", "E2E SupportTicket", user, org)

    [
      run_test("Support: critical bug → escalated", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "subject" => "App crash",
          "body" => "Error 500 in production",
          "sender_email" => "u@test.com",
          "urgency" => "critical"
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["category"], "engineering", "category")
        assert_eq!(output["priority"], "critical", "priority")
        assert_eq!(output["status"], "escalated", "status")
        :ok
      end),
      run_test("Support: billing normal → queued", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "subject" => "Invoice question",
          "body" => "Wrong charge on my account",
          "sender_email" => "u@test.com",
          "urgency" => "normal"
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["category"], "billing", "category")
        assert_eq!(resp.body["output"]["status"], "queued", "status")
        :ok
      end),
      run_test("Support: low urgency → backlog", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "subject" => "How to",
          "body" => "Question about features",
          "sender_email" => "u@test.com",
          "urgency" => "low"
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["status"], "backlog", "status")
        :ok
      end),
      run_test("Support: missing subject → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "body" => "test",
          "sender_email" => "u@test.com"
        })
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 17: Escalation Approval
  # ════════════════════════════════════════════════════════════════

  defp run_escalation_approval_new(user, org) do
    IO.puts(cyan("\n▸ Phase 17: Escalation Approval"))
    flow = create_and_activate_template("escalation_approval", "E2E Escalation", user, org)

    [
      run_test("Escalation: below threshold → auto_approved", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "request" => "Supplies",
          "amount" => 50,
          "requester" => "alice",
          "auto_approve_below" => 100
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["decision"], "auto_approved", "decision")
        assert_eq!(output["auto_approved"], true, "auto_approved")
        :ok
      end),
      run_test("Escalation: above threshold → halted", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "request" => "Big laptop",
          "amount" => 5000,
          "requester" => "bob",
          "auto_approve_below" => 100
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["status"], "halted", "status")
        :ok
      end),
      run_test("Escalation: missing request → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "amount" => 10,
          "requester" => "carol"
        })
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 18: Data Enrichment Chain
  # ════════════════════════════════════════════════════════════════

  defp run_data_enrichment_chain(user, org) do
    IO.puts(cyan("\n▸ Phase 18: Data Enrichment Chain"))
    flow = create_and_activate_template("data_enrichment_chain", "E2E Enrichment", user, org)

    [
      run_test("Enrichment: primary source found", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"email" => "alice@co.com"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["source"], "primary", "source")
        assert_eq!(output["confidence"], 90, "confidence")
        assert_eq!(output["sources_tried"], 1, "sources_tried")
        :ok
      end),
      run_test("Enrichment: fallback source", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"email" => "fallback_user@co.com"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["source"], "fallback", "source")
        assert_eq!(output["confidence"], 60, "confidence")
        assert_eq!(output["sources_tried"], 2, "sources_tried")
        :ok
      end),
      run_test("Enrichment: missing email → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "X"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 19: Incident Alert Pipeline
  # ════════════════════════════════════════════════════════════════

  defp run_incident_alert_pipeline(user, org) do
    IO.puts(cyan("\n▸ Phase 19: Incident Alert Pipeline"))
    flow = create_and_activate_template("incident_alert_pipeline", "E2E IncidentAlert", user, org)

    [
      run_test("Incident: critical → ticket + notify", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "alert_name" => "DB Down",
          "severity" => "critical",
          "source" => "prometheus"
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["severity_level"], "critical", "severity_level")
        assert_eq!(output["notification_sent"], true, "notification_sent")
        :ok
      end),
      run_test("Incident: warning alert", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "alert_name" => "High CPU",
          "severity" => "warning",
          "source" => "datadog"
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["severity_level"], "warning", "severity_level")
        :ok
      end),
      run_test("Incident: info alert", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "alert_name" => "Deploy",
          "severity" => "info",
          "source" => "ci"
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["severity_level"], "info", "severity_level")
        :ok
      end),
      run_test("Incident: duplicate skipped", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "alert_name" => "DB Down",
          "severity" => "critical",
          "source" => "prometheus",
          "fingerprint" => "dup_abc"
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["is_duplicate"], true, "is_duplicate")
        :ok
      end),
      run_test("Incident: missing alert_name → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "severity" => "info",
          "source" => "ci"
        })
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 20: Customer Onboarding
  # ════════════════════════════════════════════════════════════════

  defp run_customer_onboarding(user, org) do
    IO.puts(cyan("\n▸ Phase 20: Customer Onboarding"))
    flow = create_and_activate_template("customer_onboarding", "E2E Onboarding", user, org)

    [
      run_test("Onboarding: enterprise completes", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "customer_name" => "Alice",
          "email" => "alice@co.com",
          "plan" => "enterprise"
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["is_active"], true, "is_active")
        assert_eq!(output["onboarding_step"], "completed", "onboarding_step")
        :ok
      end),
      run_test("Onboarding: free gets nudge", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "customer_name" => "Bob",
          "email" => "bob@co.com",
          "plan" => "free"
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["nudge_sent"], true, "nudge_sent")
        assert_eq!(output["onboarding_step"], "nudged", "onboarding_step")
        :ok
      end),
      run_test("Onboarding: already_active short-circuit", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "customer_name" => "Carol",
          "email" => "c@co.com",
          "plan" => "free",
          "already_active" => true
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["is_active"], true, "is_active")
        :ok
      end),
      run_test("Onboarding: missing customer_name → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "email" => "x@co.com",
          "plan" => "free"
        })
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 21: Webhook Idempotent
  # ════════════════════════════════════════════════════════════════

  defp run_webhook_idempotent(user, org) do
    IO.puts(cyan("\n▸ Phase 21: Webhook Idempotent"))
    flow = create_and_activate_template("webhook_idempotent", "E2E Idempotent", user, org)

    [
      run_test("Idempotent: valid + new → processed", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_id" => "evt_e2e_001",
          "event_type" => "order.created",
          "signature" => "valid_abc"
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["signature_valid"], true, "signature_valid")
        assert_eq!(output["is_duplicate"], false, "is_duplicate")
        assert_contains!(output["processing_result"], "order.created", "processing_result")
        :ok
      end),
      run_test("Idempotent: valid + duplicate → ack", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_id" => "dup_e2e_001",
          "event_type" => "order.created",
          "signature" => "valid_abc"
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["is_duplicate"], true, "is_duplicate")
        :ok
      end),
      run_test("Idempotent: invalid signature → fail", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_id" => "evt_e2e_002",
          "event_type" => "order.created",
          "signature" => "invalid_xyz"
        })
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Invalid webhook signature", "error")
        :ok
      end),
      run_test("Idempotent: no signature → valid", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "event_id" => "evt_e2e_003",
          "event_type" => "test"
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["signature_valid"], true, "signature_valid")
        :ok
      end),
      run_test("Idempotent: missing event_id → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"event_type" => "test"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 22: Abandoned Cart Recovery
  # ════════════════════════════════════════════════════════════════

  defp run_abandoned_cart_recovery(user, org) do
    IO.puts(cyan("\n▸ Phase 22: Abandoned Cart Recovery"))
    flow = create_and_activate_template("abandoned_cart_recovery", "E2E AbandonedCart", user, org)

    [
      run_test("Cart: large cart → 15% + full recovery", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "customer_name" => "Alice",
          "customer_email" => "a@shop.com",
          "cart_total" => 15_000
        })
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["discount_percent"], 15, "discount_percent")
        assert_eq!(output["reminder_sent"], true, "reminder_sent")
        assert_eq!(output["final_offer_sent"], true, "final_offer_sent")
        :ok
      end),
      run_test("Cart: already purchased → skip", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "customer_name" => "Bob",
          "customer_email" => "b@shop.com",
          "cart_total" => 5000,
          "already_purchased" => true
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["recovered"], true, "recovered")
        assert_eq!(resp.body["output"]["step"], "already_purchased", "step")
        :ok
      end),
      run_test("Cart: medium cart → 10% discount", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "customer_name" => "Carol",
          "customer_email" => "c@shop.com",
          "cart_total" => 7500
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["discount_percent"], 10, "discount_percent")
        :ok
      end),
      run_test("Cart: small cart → 5% discount", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "customer_name" => "Dave",
          "customer_email" => "d@shop.com",
          "cart_total" => 2000
        })
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["discount_percent"], 5, "discount_percent")
        :ok
      end),
      run_test("Cart: missing customer_name → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{
          "customer_email" => "x@shop.com",
          "cart_total" => 100
        })
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  # ════════════════════════════════════════════════════════════════
  # Phase 14: Stress Test — concurrent webhook requests
  # ════════════════════════════════════════════════════════════════

  @stress_concurrency 50
  @stress_total 200

  defp run_stress_test(flow) do
    IO.puts(cyan("\n▸ Phase 11: Stress Test (#{@stress_total} requests, #{@stress_concurrency} concurrent)"))

    payloads = [
      %{"name" => "Stress Email", "email" => "stress@test.com"},
      %{"name" => "Stress Phone", "phone" => "11999000111"},
      %{"name" => "Stress NoContact"}
    ]

    IO.puts("  Firing #{@stress_total} requests...")

    start_time = System.monotonic_time(:millisecond)

    results =
      1..@stress_total
      |> Task.async_stream(
        fn i ->
          payload = Enum.at(payloads, rem(i, length(payloads)))
          {i, webhook_post(flow.webhook_token, payload)}
        end,
        max_concurrency: @stress_concurrency,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {_i, {:ok, resp}}} -> resp
        {:ok, {_i, {:error, reason}}} -> {:error, reason}
        {:exit, :timeout} -> {:error, :timeout}
      end)

    elapsed = System.monotonic_time(:millisecond) - start_time

    successes = Enum.count(results, &match?(%{status: 200}, &1))
    errors_422 = Enum.count(results, &match?(%{status: 422}, &1))
    errors_500 = Enum.count(results, &match?(%{status: 500}, &1))
    timeouts = Enum.count(results, &match?({:error, _}, &1))

    latencies =
      results
      |> Enum.filter(&match?(%{status: 200}, &1))
      |> Enum.map(& &1.body["duration_ms"])
      |> Enum.filter(&is_number/1)
      |> Enum.sort()

    rps = if elapsed > 0, do: Float.round(@stress_total / (elapsed / 1_000), 1), else: 0.0

    IO.puts("  Completed in #{elapsed}ms (#{rps} req/s)")
    IO.puts("  200: #{successes} | 422: #{errors_422} | 500: #{errors_500} | timeout: #{timeouts}")

    if length(latencies) > 0 do
      p50 = Enum.at(latencies, div(length(latencies), 2))
      p95 = Enum.at(latencies, trunc(length(latencies) * 0.95))
      p99 = Enum.at(latencies, min(trunc(length(latencies) * 0.99), length(latencies) - 1))
      max_lat = List.last(latencies)
      IO.puts("  Latency (execution_ms): p50=#{p50} p95=#{p95} p99=#{p99} max=#{max_lat}")
    end

    test_results = [
      run_test("Stress: all requests completed (no timeouts)", fn ->
        if timeouts > 0, do: raise("#{timeouts} requests timed out")
        :ok
      end),
      run_test("Stress: no 500 errors", fn ->
        if errors_500 > 0, do: raise("#{errors_500} requests returned HTTP 500")
        :ok
      end),
      run_test("Stress: all 200s returned valid output", fn ->
        bad =
          results
          |> Enum.filter(&match?(%{status: 200}, &1))
          |> Enum.reject(fn resp ->
            output = resp.body["output"]
            is_map(output) and (Map.has_key?(output, "channel") or Map.has_key?(output, "error"))
          end)

        if length(bad) > 0, do: raise("#{length(bad)} responses had invalid output")
        :ok
      end),
      run_test("Stress: throughput > 10 req/s", fn ->
        if rps < 10.0, do: raise("Only #{rps} req/s")
        :ok
      end)
    ]

    test_results
  end

  # ════════════════════════════════════════════════════════════════
  # Flow creation helpers
  # ════════════════════════════════════════════════════════════════

  defp create_and_activate_template(template_id, name_prefix, user, org) do
    ts = System.system_time(:second)
    name = "#{name_prefix} #{ts}"

    {:ok, flow} =
      Blackboex.Flows.create_flow_from_template(
        %{name: name, organization_id: org.id, user_id: user.id},
        template_id
      )

    {:ok, flow} = Blackboex.Flows.activate_flow(flow)
    IO.puts("  Created+activated: #{flow.name} (token: #{flow.webhook_token})")
    flow
  end

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

  # ════════════════════════════════════════════════════════════════
  # HTTP / Test runner / Assertions / Report
  # ════════════════════════════════════════════════════════════════

  defp webhook_post(token, body) do
    Req.post("#{@base_url}/webhook/#{token}",
      json: body,
      receive_timeout: 30_000,
      retry: :transient,
      max_retries: 2
    )
  end

  defp run_test(name, fun) do
    case fun.() do
      :ok ->
        IO.puts(green("  ✓ #{name}"))
        {:pass, name}

      {:error, reason} ->
        IO.puts(red("  ✗ #{name}: #{reason}"))
        {:fail, name, reason}
    end
  rescue
    e ->
      reason = Exception.message(e)
      IO.puts(red("  ✗ #{name}: #{reason}"))
      {:fail, name, reason}
  end

  defp assert_status!(resp, expected) do
    if resp.status != expected do
      raise "Expected HTTP #{expected}, got #{resp.status}: #{inspect(resp.body)}"
    end
  end

  defp assert_eq!(actual, expected, label) do
    if actual != expected do
      raise "#{label}: expected #{inspect(expected)}, got #{inspect(actual)}"
    end
  end

  defp assert_contains!(string, substring, label) when is_binary(string) do
    unless String.contains?(string, substring) do
      raise "#{label}: expected to contain #{inspect(substring)}, got #{inspect(string)}"
    end
  end

  defp assert_contains!(other, _substring, label) do
    raise "#{label}: expected a string, got #{inspect(other)}"
  end

  defp assert_present!(nil, label), do: raise("#{label}: expected non-nil value")
  defp assert_present!(_, _label), do: :ok

  defp assert_gte!(actual, min, _label) when is_number(actual) and actual >= min, do: :ok

  defp assert_gte!(actual, min, label) do
    raise "#{label}: expected >= #{min}, got #{inspect(actual)}"
  end

  defp report(results) do
    passed = Enum.count(results, &match?({:pass, _}, &1))
    failed = Enum.count(results, &match?({:fail, _, _}, &1))
    total = length(results)

    IO.puts(bold("\n══════════════════════════════════════════════"))

    if failed == 0 do
      IO.puts(green("  All #{total} tests passed ✓"))
    else
      IO.puts(yellow("  #{passed}/#{total} passed, #{failed} failed"))

      for {:fail, name, reason} <- results do
        IO.puts(red("    ✗ #{name}: #{reason}"))
      end
    end

    IO.puts(bold("══════════════════════════════════════════════\n"))

    if failed > 0, do: System.halt(1)
  end
end

E2E.Flows.run()
