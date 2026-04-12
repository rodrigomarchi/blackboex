defmodule E2E.Phase.Notification do
  import E2E.Helpers

  def run(flow) do
    IO.puts(cyan("\n▸ Phase 2: Notification Sub-Flow"))

    [
      run_test("Notif: email channel", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{"message" => "Hello World", "channel" => "email"})

        assert_status!(resp, 200)

        assert_eq!(
          resp.body["output"]["formatted"],
          "Notification via email: Hello World",
          "formatted"
        )

        :ok
      end),
      run_test("Notif: sms channel", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{"message" => "Alert!", "channel" => "sms"})

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

  def stress_scenarios do
    [
      %{
        name: "email channel",
        input: %{"message" => "Hello World", "channel" => "email"},
        verify: fn resp ->
          if resp.status == 200 and
               resp.body["output"]["formatted"] == "Notification via email: Hello World" do
            :ok
          else
            {:error, "expected formatted notification, got #{inspect(resp.body["output"])}"}
          end
        end
      },
      %{
        name: "sms channel",
        input: %{"message" => "Alert!", "channel" => "sms"},
        verify: fn resp ->
          if resp.status == 200 and
               resp.body["output"]["formatted"] == "Notification via sms: Alert!" do
            :ok
          else
            {:error, "expected sms notification, got #{inspect(resp.body["output"])}"}
          end
        end
      },
      %{
        name: "missing required field",
        input: %{"message" => "No channel"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
