defmodule E2E.Phase.SubFlowOrchestrator do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 30: Sub-flow Orchestrator"))
    flow = create_and_activate_template("sub_flow_orchestrator", "E2E SubFlow", user, org)

    [
      run_test("SubFlow: valid order with items → confirmed", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "order_id" => "e2e_sfo_001",
            "customer_id" => "e2e_cus_001",
            "items" => [%{"sku" => "WIDGET-1", "qty" => 2}],
            "total_amount" => 5999
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["order_status"], "confirmed", "order_status")
        assert_eq!(output["payment_valid"], true, "payment_valid")
        assert_eq!(output["inventory_available"], true, "inventory_available")
        :ok
      end),
      run_test("SubFlow: empty items → inventory_hold", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "order_id" => "e2e_sfo_002",
            "customer_id" => "e2e_cus_002",
            "items" => [],
            "total_amount" => 1000
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["order_status"], "inventory_hold", "order_status")
        :ok
      end),
      run_test("SubFlow: total_amount=0 → payment_failed (422)", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "order_id" => "e2e_sfo_003",
            "customer_id" => "e2e_cus_003",
            "items" => [%{"sku" => "X", "qty" => 1}],
            "total_amount" => 0
          })

        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payment validation failed", "error")
        :ok
      end),
      run_test("SubFlow: payment and inventory results are maps", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "order_id" => "e2e_sfo_004",
            "customer_id" => "e2e_cus_004",
            "items" => [%{"sku" => "A", "qty" => 1}],
            "total_amount" => 999
          })

        assert_status!(resp, 200)
        output = resp.body["output"]

        unless is_map(output["payment_result"]) do
          raise "payment_result is not a map: #{inspect(output["payment_result"])}"
        end

        unless is_map(output["inventory_result"]) do
          raise "inventory_result is not a map: #{inspect(output["inventory_result"])}"
        end

        :ok
      end),
      run_test("SubFlow: missing order_id → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "customer_id" => "e2e_cus_x",
            "items" => [],
            "total_amount" => 100
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
        name: "valid order → confirmed",
        input: %{
          "order_id" => "stress_sfo_001",
          "customer_id" => "stress_cus_001",
          "items" => [%{"sku" => "WIDGET-1", "qty" => 2}],
          "total_amount" => 5999
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["order_status"] == "confirmed" do
            :ok
          else
            {:error, "expected order_status=confirmed, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "total_amount=0 → payment_failed",
        input: %{
          "order_id" => "stress_sfo_002",
          "customer_id" => "stress_cus_002",
          "items" => [%{"sku" => "X", "qty" => 1}],
          "total_amount" => 0
        },
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      },
      %{
        name: "missing order_id",
        input: %{"customer_id" => "c-x", "items" => [], "total_amount" => 100},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
