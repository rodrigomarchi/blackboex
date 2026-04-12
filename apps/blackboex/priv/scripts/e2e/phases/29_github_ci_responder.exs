defmodule E2E.Phase.GithubCiResponder do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 29: GitHub CI Responder"))
    flow = create_and_activate_template("github_ci_responder", "E2E GithubCI", user, org)

    [
      run_test("CI: build_failed → ticket_created", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "build_failed",
            "repository" => "myorg/api",
            "branch" => "main",
            "actor" => "github-actions",
            "build_url" => "https://ci.example.com/123"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["action_taken"], "ticket_created", "action_taken")
        assert_eq!(output["notification_sent"], true, "notification_sent")
        :ok
      end),
      run_test("CI: pr_merged → merge_notified", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "pr_merged",
            "repository" => "myorg/api",
            "branch" => "feature/auth",
            "actor" => "john",
            "pr_number" => 42
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["action_taken"], "merge_notified", "action_taken")
        :ok
      end),
      run_test("CI: deployment_success → deploy_triggered", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "deployment_success",
            "repository" => "myorg/api",
            "branch" => "main",
            "actor" => "github-actions"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["action_taken"], "deploy_triggered", "action_taken")
        assert_eq!(output["deploy_triggered"], true, "deploy_triggered")
        :ok
      end),
      run_test("CI: pr_opened → pr_acknowledged", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "pr_opened",
            "repository" => "myorg/api",
            "branch" => "feature/new-ui",
            "actor" => "jane",
            "pr_number" => 43
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["action_taken"], "pr_acknowledged", "action_taken")
        :ok
      end),
      run_test("CI: missing repository → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "event_type" => "build_failed",
            "branch" => "main",
            "actor" => "ci"
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
        name: "build_failed → ticket_created",
        input: %{
          "event_type" => "build_failed",
          "repository" => "myorg/api",
          "branch" => "main",
          "actor" => "github-actions",
          "build_url" => "https://ci.example.com/123"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["action_taken"] == "ticket_created" do
            :ok
          else
            {:error, "expected action_taken=ticket_created, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "pr_merged → merge_notified",
        input: %{
          "event_type" => "pr_merged",
          "repository" => "myorg/api",
          "branch" => "feature/auth",
          "actor" => "john",
          "pr_number" => 42
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["action_taken"] == "merge_notified" do
            :ok
          else
            {:error, "expected action_taken=merge_notified, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing repository",
        input: %{"event_type" => "build_failed", "branch" => "main", "actor" => "ci"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
