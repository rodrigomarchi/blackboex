defmodule E2E.Phase.SlaMonitor do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 27: SLA Monitor"))
    flow = create_and_activate_template("sla_monitor", "E2E SlaMonitor", user, org)

    [
      run_test("SLA: critical breach detected → breached_count=1", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "tickets" => [
              %{
                "id" => "T1",
                "priority" => "critical",
                "age_hours" => 3,
                "title" => "DB down",
                "assignee" => "ops-team"
              }
            ]
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["breached_count"], 1, "breached_count")
        :ok
      end),
      run_test("SLA: no breach → all_clear path", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "tickets" => [
              %{
                "id" => "T1",
                "priority" => "normal",
                "age_hours" => 1,
                "title" => "Question",
                "assignee" => "support"
              }
            ]
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["breached_count"], 0, "breached_count")
        :ok
      end),
      run_test("SLA: empty tickets → total_tickets=0", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"tickets" => []})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["total_tickets"], 0, "total_tickets")
        assert_eq!(output["breached_count"], 0, "breached_count")
        :ok
      end),
      run_test("SLA: report_generated_at is set", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "tickets" => [
              %{
                "id" => "T1",
                "priority" => "high",
                "age_hours" => 1,
                "title" => "T",
                "assignee" => "x"
              }
            ]
          })

        assert_status!(resp, 200)
        assert_present!(resp.body["output"]["report_generated_at"], "report_generated_at")
        :ok
      end),
      run_test("SLA: missing tickets → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"sla_thresholds" => %{}})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "breach detected",
        input: %{
          "tickets" => [
            %{
              "id" => "T1",
              "priority" => "critical",
              "age_hours" => 3,
              "title" => "DB down",
              "assignee" => "ops-team"
            }
          ]
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["breached_count"] >= 1 do
            :ok
          else
            {:error, "expected breached_count >= 1, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "no breach",
        input: %{
          "tickets" => [
            %{
              "id" => "T1",
              "priority" => "normal",
              "age_hours" => 1,
              "title" => "Question",
              "assignee" => "support"
            }
          ]
        },
        verify: fn resp ->
          if resp.status == 200, do: :ok, else: {:error, "expected 200, got #{resp.status}"}
        end
      },
      %{
        name: "missing tickets",
        input: %{"sla_thresholds" => %{}},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
