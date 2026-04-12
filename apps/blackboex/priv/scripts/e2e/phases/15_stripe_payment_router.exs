defmodule E2E.Phase.StripePaymentRouter do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 15: Stripe Payment Router"))
    flow = create_and_activate_template("stripe_payment_router", "E2E StripePayment", user, org)

    [
      run_test("Stripe: payment.succeeded → fulfill_order", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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

  def stress_scenarios do
    [
      %{
        name: "payment.succeeded → fulfill_order",
        input: %{
          "event_type" => "payment.succeeded",
          "payment_id" => "pi_stress_001",
          "amount" => 4999,
          "customer_id" => "cus_stress_001"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["action"] == "fulfill_order" do
            :ok
          else
            {:error, "expected action=fulfill_order, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "payment.failed → retry_payment",
        input: %{
          "event_type" => "payment.failed",
          "payment_id" => "pi_stress_002",
          "amount" => 1000,
          "customer_id" => "cus_stress_002"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["action"] == "retry_payment" do
            :ok
          else
            {:error, "expected action=retry_payment, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing event_type",
        input: %{"payment_id" => "pi_stress_003", "amount" => 1, "customer_id" => "cus_003"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
