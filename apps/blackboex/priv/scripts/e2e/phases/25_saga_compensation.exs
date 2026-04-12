defmodule E2E.Phase.SagaCompensation do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 25: Saga Compensation"))
    flow = create_and_activate_template("saga_compensation", "E2E SagaCompensation", user, org)

    [
      run_test("Saga: all steps succeed → completed", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "order_id" => "e2e_ord_001",
            "customer_id" => "e2e_cus_001",
            "amount" => 9999,
            "items" => [%{"sku" => "WIDGET-1", "qty" => 2}]
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["saga_status"], "completed", "saga_status")
        assert_eq!(output["inventory_reserved"], true, "inventory_reserved")
        assert_eq!(output["payment_charged"], true, "payment_charged")
        assert_eq!(output["shipment_created"], true, "shipment_created")
        :ok
      end),
      run_test("Saga: fail at inventory → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "order_id" => "e2e_ord_002",
            "customer_id" => "e2e_cus_002",
            "amount" => 1000,
            "items" => [],
            "simulate_failure_at" => "inventory"
          })

        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Inventory", "error")
        :ok
      end),
      run_test("Saga: fail at payment → 422 + compensation", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "order_id" => "e2e_ord_003",
            "customer_id" => "e2e_cus_003",
            "amount" => 5000,
            "items" => [%{"sku" => "THING-1", "qty" => 1}],
            "simulate_failure_at" => "payment"
          })

        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payment", "error")
        :ok
      end),
      run_test("Saga: fail at shipment → 422 + full compensation", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "order_id" => "e2e_ord_004",
            "customer_id" => "e2e_cus_004",
            "amount" => 2000,
            "items" => [%{"sku" => "GADGET-1", "qty" => 1}],
            "simulate_failure_at" => "shipment"
          })

        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Shipment", "error")
        :ok
      end),
      run_test("Saga: missing order_id → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "customer_id" => "e2e_cus_x",
            "amount" => 100,
            "items" => []
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
        name: "all steps succeed",
        input: %{
          "order_id" => "stress_ord_001",
          "customer_id" => "stress_cus_001",
          "amount" => 9999,
          "items" => [%{"sku" => "WIDGET-1", "qty" => 2}]
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["saga_status"] == "completed" do
            :ok
          else
            {:error, "expected saga_status=completed, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "fail at payment → 422",
        input: %{
          "order_id" => "stress_ord_002",
          "customer_id" => "stress_cus_002",
          "amount" => 5000,
          "items" => [%{"sku" => "THING-1", "qty" => 1}],
          "simulate_failure_at" => "payment"
        },
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      },
      %{
        name: "missing order_id",
        input: %{"customer_id" => "c-x", "amount" => 100, "items" => []},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
