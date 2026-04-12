defmodule E2E.Phase.LeadScoring do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 12: Lead Scoring (debug + scoring + fail)"))
    flow = create_and_activate_template("lead_scoring", "E2E LeadScore", user, org)

    [
      run_test("Lead: qualified (email+company+budget) → success", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "name" => "Alice",
            "email" => "alice@bigcorp.com",
            "company" => "BigCorp",
            "budget" => 5000
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["status"], "qualified", "status")
        assert_eq!(output["name"], "Alice", "name")
        assert_eq!(output["email"], "alice@bigcorp.com", "email")
        :ok
      end),
      run_test("Lead: score=100 in shared_state", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "name" => "ScoreCheck",
            "email" => "sc@co.com",
            "company" => "Co",
            "budget" => 2000
          })

        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        # email(+20) + company(+30) + budget>1000(+50) = 100
        assert_eq!(exec.shared_state["score"], 100, "score")
        assert_eq!(exec.shared_state["qualified"], true, "qualified")
        assert_eq!(exec.shared_state["enriched"], true, "enriched")
        :ok
      end),
      run_test("Lead: unqualified (email only, score=20) → fail", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "name" => "Charlie",
            "email" => "charlie@test.com"
          })

        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "not qualified", "error mentions not qualified")
        :ok
      end),
      run_test("Lead: debug stores lead data", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "name" => "DebugLead",
            "email" => "dl@test.com",
            "company" => "TestCo",
            "budget" => 9999
          })

        assert_status!(resp, 200)
        exec = Blackboex.FlowExecutions.get_execution(resp.body["execution_id"])
        assert_present!(exec.shared_state["debug_lead"], "debug_lead in state")
        assert_eq!(exec.shared_state["debug_lead"]["name"], "DebugLead", "debug captured name")
        assert_eq!(exec.shared_state["debug_lead"]["company"], "TestCo", "debug captured company")
        :ok
      end),
      run_test("Lead: skip_scoring bypasses scoring → success", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "name" => "SkipScore",
            "email" => "ss@test.com",
            "skip_scoring" => true
          })

        assert_status!(resp, 200)
        # Skipped scoring → condition sees nil qualified → branch 0 (success)
        assert_present!(resp.body["output"], "has output")
        :ok
      end),
      run_test("Lead: no email, no company, no budget → score=0 → fail", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "NoInfo"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "not qualified", "error mentions not qualified")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "qualified lead",
        input: %{
          "name" => "Alice",
          "email" => "alice@bigcorp.com",
          "company" => "BigCorp",
          "budget" => 5000
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["status"] == "qualified" do
            :ok
          else
            {:error, "expected status=qualified, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "unqualified lead (email only)",
        input: %{"name" => "Charlie", "email" => "charlie@test.com"},
        verify: fn resp ->
          if resp.status == 422 do
            :ok
          else
            {:error, "expected 422 (fail node → not qualified), got #{resp.status}"}
          end
        end
      },
      %{
        name: "missing email",
        input: %{"name" => "NoInfo"},
        verify: fn resp ->
          if resp.status == 422 do
            :ok
          else
            {:error, "expected 422 (fail node → not qualified), got #{resp.status}"}
          end
        end
      }
    ]
  end
end
