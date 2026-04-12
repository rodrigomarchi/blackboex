defmodule E2E.Phase.SupportTicketRouter do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 16: Support Ticket Router"))
    flow = create_and_activate_template("support_ticket_router", "E2E SupportTicket", user, org)

    [
      run_test("Support: critical bug → escalated", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "subject" => "App crash",
            "body" => "Error 500 in production",
            "sender_email" => "u@test.com",
            "urgency" => "critical"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["category"], "engineering", "category")
        assert_eq!(output["priority"], "critical", "priority")
        assert_eq!(output["status"], "escalated", "status")
        :ok
      end),
      run_test("Support: billing normal → queued", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "subject" => "Invoice question",
            "body" => "Wrong charge on my account",
            "sender_email" => "u@test.com",
            "urgency" => "normal"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["category"], "billing", "category")
        assert_eq!(resp.body["output"]["status"], "queued", "status")
        :ok
      end),
      run_test("Support: low urgency → backlog", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "subject" => "How to",
            "body" => "Question about features",
            "sender_email" => "u@test.com",
            "urgency" => "low"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["status"], "backlog", "status")
        :ok
      end),
      run_test("Support: missing subject → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "body" => "test",
            "sender_email" => "u@test.com"
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
        name: "critical bug → escalated",
        input: %{
          "subject" => "App crash",
          "body" => "Error 500 in production",
          "sender_email" => "u@test.com",
          "urgency" => "critical"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["status"] == "escalated" do
            :ok
          else
            {:error, "expected status=escalated, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "billing normal → queued",
        input: %{
          "subject" => "Invoice question",
          "body" => "Wrong charge on my account",
          "sender_email" => "u@test.com",
          "urgency" => "normal"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["status"] == "queued" do
            :ok
          else
            {:error, "expected status=queued, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing subject",
        input: %{"body" => "test", "sender_email" => "u@test.com"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
