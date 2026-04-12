defmodule E2E.Phase.CustomerOnboarding do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 20: Customer Onboarding"))
    flow = create_and_activate_template("customer_onboarding", "E2E Onboarding", user, org)

    [
      run_test("Onboarding: enterprise completes", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "customer_name" => "Alice",
            "email" => "alice@co.com",
            "plan" => "enterprise"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["is_active"], true, "is_active")
        assert_eq!(output["onboarding_step"], "completed", "onboarding_step")
        :ok
      end),
      run_test("Onboarding: free gets nudge", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "customer_name" => "Bob",
            "email" => "bob@co.com",
            "plan" => "free"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["nudge_sent"], true, "nudge_sent")
        assert_eq!(output["onboarding_step"], "nudged", "onboarding_step")
        :ok
      end),
      run_test("Onboarding: already_active short-circuit", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "customer_name" => "Carol",
            "email" => "c@co.com",
            "plan" => "free",
            "already_active" => true
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["is_active"], true, "is_active")
        :ok
      end),
      run_test("Onboarding: missing customer_name → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "email" => "x@co.com",
            "plan" => "free"
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
        name: "enterprise plan",
        input: %{
          "customer_name" => "Alice",
          "email" => "alice@co.com",
          "plan" => "enterprise"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["onboarding_step"] == "completed" do
            :ok
          else
            {:error, "expected onboarding_step=completed, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "free plan",
        input: %{"customer_name" => "Bob", "email" => "bob@co.com", "plan" => "free"},
        verify: fn resp ->
          if resp.status == 200, do: :ok, else: {:error, "expected 200, got #{resp.status}"}
        end
      },
      %{
        name: "missing customer_name",
        input: %{"email" => "x@co.com", "plan" => "free"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
