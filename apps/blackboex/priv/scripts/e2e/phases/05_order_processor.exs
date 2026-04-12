defmodule E2E.Phase.OrderProcessor do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 5: Order Processor"))
    flow = create_and_activate_template("order_processor", "E2E OrderProc", user, org)

    [
      run_test("Order: express (qty=3)", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "item" => "Widget",
            "quantity" => 3,
            "priority" => "express"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["status"], "express_confirmed", "status")
        assert_eq!(output["total"], 55.0, "total (3*10 + 25 shipping)")
        assert_eq!(output["delivery_days"], 1, "delivery_days")
        :ok
      end),
      run_test("Order: standard (qty=5)", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "item" => "Gadget",
            "quantity" => 5,
            "priority" => "standard"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["status"], "standard_confirmed", "status")
        assert_eq!(output["total"], 55.0, "total (5*10 + 5 shipping)")
        assert_eq!(output["delivery_days"], 5, "delivery_days")
        :ok
      end),
      run_test("Order: invalid priority", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "item" => "Thing",
            "quantity" => 1,
            "priority" => "overnight"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_contains!(output["error"], "Invalid priority", "error message")
        assert_contains!(output["error"], "overnight", "mentions priority value")
        :ok
      end),
      run_test("Order: quantity=0 edge case", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "item" => "Free",
            "quantity" => 0,
            "priority" => "express"
          })

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

  def stress_scenarios do
    [
      %{
        name: "express qty=3",
        input: %{"item" => "Widget", "quantity" => 3, "priority" => "express"},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["status"] == "express_confirmed" do
            :ok
          else
            {:error, "expected status=express_confirmed, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "standard qty=5",
        input: %{"item" => "Gadget", "quantity" => 5, "priority" => "standard"},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["status"] == "standard_confirmed" do
            :ok
          else
            {:error, "expected status=standard_confirmed, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing product_id",
        input: %{"item" => "X"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
