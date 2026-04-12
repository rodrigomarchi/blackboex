defmodule E2E.Phase.NotificationFanout do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 26: Notification Fanout"))
    flow = create_and_activate_template("notification_fanout", "E2E NotifFanout", user, org)

    [
      run_test("Fanout: critical → 3 channels", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "alert",
            "title" => "DB Down",
            "message" => "Primary DB unreachable",
            "severity" => "critical"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["notifications_sent"], 3, "notifications_sent")
        assert_gte!(length(output["channels"]), 3, "channels count")
        :ok
      end),
      run_test("Fanout: high → 2 channels", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "alert",
            "title" => "High CPU",
            "message" => "CPU at 95%",
            "severity" => "high"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["notifications_sent"], 2, "notifications_sent")
        :ok
      end),
      run_test("Fanout: medium → 1 channel", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "deploy",
            "title" => "Deploy done",
            "message" => "v1.2.3 deployed",
            "severity" => "medium"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["notifications_sent"], 1, "notifications_sent")
        :ok
      end),
      run_test("Fanout: results have status=sent", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "alert",
            "title" => "Critical",
            "message" => "System down",
            "severity" => "critical"
          })

        assert_status!(resp, 200)
        results = resp.body["output"]["results"]

        unless Enum.all?(results, fn r -> r["status"] == "sent" end) do
          raise "Not all results have status=sent: #{inspect(results)}"
        end

        :ok
      end),
      run_test("Fanout: missing severity → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "deploy",
            "title" => "Test",
            "message" => "msg"
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
        name: "critical → 3 channels",
        input: %{
          "event_type" => "alert",
          "title" => "DB Down",
          "message" => "Primary DB unreachable",
          "severity" => "critical"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["notifications_sent"] >= 3 do
            :ok
          else
            {:error, "expected notifications_sent >= 3, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "high → 2 channels",
        input: %{
          "event_type" => "alert",
          "title" => "High CPU",
          "message" => "CPU at 95%",
          "severity" => "high"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["notifications_sent"] >= 2 do
            :ok
          else
            {:error, "expected notifications_sent >= 2, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing severity",
        input: %{"event_type" => "deploy", "title" => "Test", "message" => "msg"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
