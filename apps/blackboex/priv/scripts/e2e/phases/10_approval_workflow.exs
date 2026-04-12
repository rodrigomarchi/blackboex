defmodule E2E.Phase.ApprovalWorkflow do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 10: Approval Workflow (auto-approve branch)"))
    flow = create_and_activate_template("approval_workflow", "E2E Approval", user, org)

    [
      run_test("Approval: auto-approve (amount < threshold)", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "request" => "Buy supplies",
            "amount" => 50,
            "auto_approve_below" => 100
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["decision"], "auto_approved", "decision")
        assert_eq!(output["approved_by"], "system", "approved_by")
        assert_contains!(output["reason"], "50", "reason mentions amount")
        :ok
      end),
      run_test("Approval: auto-approve (no threshold = always auto)", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "request" => "Small purchase",
            "amount" => 1000
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["decision"], "auto_approved", "decision")
        :ok
      end),
      run_test("Approval: halts when amount >= threshold (returns halted status)", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "request" => "Big purchase",
            "amount" => 500,
            "auto_approve_below" => 100
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["status"], "halted", "status")
        assert_present!(resp.body["execution_id"], "execution_id")
        assert_contains!(resp.body["resume_url"], flow.webhook_token, "resume_url has token")
        :ok
      end),
      run_test("Approval: missing required field", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"amount" => 10})
        # After a halt, connections may reset. Use a fresh request.
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "auto-approve (amount < threshold)",
        input: %{"request" => "Buy supplies", "amount" => 50, "auto_approve_below" => 100},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["decision"] == "auto_approved" do
            :ok
          else
            {:error, "expected decision=auto_approved, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "halted (amount >= threshold)",
        input: %{"request" => "Big purchase", "amount" => 500, "auto_approve_below" => 100},
        verify: fn resp ->
          if resp.status == 200 and resp.body["status"] == "halted" do
            :ok
          else
            {:error,
             "expected status=200 with body.status=halted, got status=#{resp.status} body=#{inspect(resp.body)}"}
          end
        end
      },
      %{
        name: "missing required field",
        input: %{"amount" => 10},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
