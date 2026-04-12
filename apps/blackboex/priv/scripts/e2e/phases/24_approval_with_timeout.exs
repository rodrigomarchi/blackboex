defmodule E2E.Phase.ApprovalWithTimeout do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 24: Approval with Timeout"))
    flow = create_and_activate_template("approval_with_timeout", "E2E ApprovalTimeout", user, org)

    [
      run_test("Approval: simulate_timeout=true → escalated", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "request_title" => "Q4 Budget",
            "requester" => "alice",
            "amount" => 50_000,
            "approver_email" => "manager@example.com",
            "simulate_timeout" => true
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["decision"], "escalated", "decision")
        assert_eq!(output["escalated"], true, "escalated")
        :ok
      end),
      run_test("Approval: no simulate_timeout → halted (webhook_wait)", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "request_title" => "Hardware Purchase",
            "requester" => "bob",
            "amount" => 1_500,
            "approver_email" => "manager@example.com"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["status"], "halted", "status")
        :ok
      end),
      run_test("Approval: reminder_sent starts false", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "request_title" => "Software License",
            "requester" => "carol",
            "amount" => 500,
            "approver_email" => "mgr@example.com",
            "simulate_timeout" => true
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["reminder_sent"], false, "reminder_sent")
        :ok
      end),
      run_test("Approval: missing request_title → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "requester" => "x",
            "amount" => 100,
            "approver_email" => "m@example.com"
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
        name: "simulate_timeout=true → escalated",
        input: %{
          "request_title" => "Q4 Budget",
          "requester" => "alice",
          "amount" => 50_000,
          "approver_email" => "manager@example.com",
          "simulate_timeout" => true
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["decision"] == "escalated" do
            :ok
          else
            {:error, "expected decision=escalated, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "no timeout → halted",
        input: %{
          "request_title" => "Hardware Purchase",
          "requester" => "bob",
          "amount" => 1_500,
          "approver_email" => "manager@example.com"
        },
        verify: fn resp ->
          if resp.status == 200 and resp.body["status"] == "halted" do
            :ok
          else
            {:error,
             "expected body.status=halted, got status=#{resp.status} body=#{inspect(resp.body)}"}
          end
        end
      },
      %{
        name: "missing request_title",
        input: %{"requester" => "x", "amount" => 100, "approver_email" => "m@example.com"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
