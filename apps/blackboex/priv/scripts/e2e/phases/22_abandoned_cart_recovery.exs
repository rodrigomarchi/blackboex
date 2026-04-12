defmodule E2E.Phase.AbandonedCartRecovery do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 22: Abandoned Cart Recovery"))
    flow = create_and_activate_template("abandoned_cart_recovery", "E2E AbandonedCart", user, org)

    [
      run_test("Cart: large cart → 15% + full recovery", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "customer_name" => "Carol",
            "customer_email" => "c@shop.com",
            "cart_total" => 7500
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["discount_percent"], 10, "discount_percent")
        :ok
      end),
      run_test("Cart: small cart → 5% discount", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "customer_name" => "Dave",
            "customer_email" => "d@shop.com",
            "cart_total" => 2000
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["discount_percent"], 5, "discount_percent")
        :ok
      end),
      run_test("Cart: missing customer_name → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "customer_email" => "x@shop.com",
            "cart_total" => 100
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
        name: "large cart value=300",
        input: %{
          "customer_name" => "Alice",
          "customer_email" => "a@shop.com",
          "cart_total" => 300
        },
        verify: fn resp ->
          if resp.status == 200, do: :ok, else: {:error, "expected 200, got #{resp.status}"}
        end
      },
      %{
        name: "already purchased",
        input: %{
          "customer_name" => "Bob",
          "customer_email" => "b@shop.com",
          "cart_total" => 5000,
          "already_purchased" => true
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["recovered"] == true do
            :ok
          else
            {:error, "expected recovered=true, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing customer_name",
        input: %{"customer_email" => "x@shop.com", "cart_total" => 100},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
