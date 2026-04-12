defmodule E2E.Phase.WebhookProcessor do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 13: Webhook Processor (3-way branch + delay + fail)"))
    flow = create_and_activate_template("webhook_processor", "E2E WebhookProc", user, org)

    [
      run_test("Webhook: order.created → order processed", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "invoice.voided",
            "timestamp" => "2026-04-10T12:00:00Z"
          })

        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Unsupported event type", "error message")
        :ok
      end),
      run_test("Webhook: test event skips validation → order path", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "test",
            "payload" => %{"id" => "TEST-001"}
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["action"], "order_processed", "action")
        :ok
      end),
      run_test("Webhook: debug stores event info", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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

  def stress_scenarios do
    [
      %{
        name: "order.created event",
        input: %{
          "event_type" => "order.created",
          "payload" => %{"id" => "ORD-001", "amount" => 99.90},
          "timestamp" => "2026-04-10T12:00:00Z"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["action"] == "order_processed" do
            :ok
          else
            {:error, "expected action=order_processed, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "payment.received event",
        input: %{
          "event_type" => "payment.received",
          "payload" => %{"id" => "PAY-001"},
          "timestamp" => "2026-04-10T12:00:00Z"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["action"] == "payment_processed" do
            :ok
          else
            {:error, "expected action=payment_processed, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing event_type",
        input: %{"payload" => %{"id" => "1"}},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
