defmodule E2E.Phase.WebhookIdempotent do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 21: Webhook Idempotent"))
    flow = create_and_activate_template("webhook_idempotent", "E2E Idempotent", user, org)

    [
      run_test("Idempotent: valid + new → processed", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_id" => "dup_e2e_001",
            "event_type" => "order.created",
            "signature" => "valid_abc"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["is_duplicate"], true, "is_duplicate")
        :ok
      end),
      run_test("Idempotent: invalid signature → fail", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_id" => "evt_e2e_002",
            "event_type" => "order.created",
            "signature" => "invalid_xyz"
          })

        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Invalid webhook signature", "error")
        :ok
      end),
      run_test("Idempotent: no signature → valid", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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

  def stress_scenarios do
    [
      %{
        name: "new event",
        input: fn ->
          %{
            "event_id" => "stress-#{:rand.uniform(999_999_999)}",
            "event_type" => "order.created",
            "signature" => "valid_abc"
          }
        end,
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and is_binary(output["processing_result"]) do
            :ok
          else
            {:error, "expected processing_result present, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing event_id",
        input: %{"event_type" => "test"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
