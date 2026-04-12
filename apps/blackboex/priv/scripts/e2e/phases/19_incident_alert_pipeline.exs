defmodule E2E.Phase.IncidentAlertPipeline do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 19: Incident Alert Pipeline"))
    flow = create_and_activate_template("incident_alert_pipeline", "E2E IncidentAlert", user, org)

    [
      run_test("Incident: critical → ticket + notify", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "alert_name" => "High CPU",
            "severity" => "warning",
            "source" => "datadog"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["severity_level"], "warning", "severity_level")
        :ok
      end),
      run_test("Incident: info alert", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "alert_name" => "Deploy",
            "severity" => "info",
            "source" => "ci"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["severity_level"], "info", "severity_level")
        :ok
      end),
      run_test("Incident: duplicate skipped", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
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
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "severity" => "info",
            "source" => "ci"
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
        name: "critical alert",
        input: %{
          "alert_name" => "DB Down",
          "severity" => "critical",
          "source" => "prometheus"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["severity_level"] == "critical" and
               output["notification_sent"] == true do
            :ok
          else
            {:error,
             "expected severity_level=critical + notification_sent=true, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "warning alert",
        input: %{"alert_name" => "High CPU", "severity" => "warning", "source" => "datadog"},
        verify: fn resp ->
          if resp.status == 200, do: :ok, else: {:error, "expected 200, got #{resp.status}"}
        end
      },
      %{
        name: "missing alert_name",
        input: %{"severity" => "info", "source" => "ci"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
