defmodule E2E.Phase.EscalationApproval do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 17: Escalation Approval"))
    flow = create_and_activate_template("escalation_approval", "E2E Escalation", user, org)

    [
      run_test("Escalation: below threshold → auto_approved", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "request" => "Supplies",
            "amount" => 50,
            "requester" => "alice",
            "auto_approve_below" => 100
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["decision"], "auto_approved", "decision")
        assert_eq!(output["auto_approved"], true, "auto_approved")
        :ok
      end),
      run_test("Escalation: above threshold → halted", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "request" => "Big laptop",
            "amount" => 5000,
            "requester" => "bob",
            "auto_approve_below" => 100
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["status"], "halted", "status")
        :ok
      end),
      run_test("Escalation: missing request → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "amount" => 10,
            "requester" => "carol"
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
        name: "below threshold auto_approved",
        input: %{
          "request" => "Supplies",
          "amount" => 50,
          "requester" => "alice",
          "auto_approve_below" => 100
        },
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
        name: "above threshold halted",
        input: %{
          "request" => "Big laptop",
          "amount" => 5000,
          "requester" => "bob",
          "auto_approve_below" => 100
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
        name: "missing request",
        input: %{"amount" => 10, "requester" => "carol"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
