defmodule E2E.Phase.AsyncJobPoller do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 28: Async Job Poller"))
    flow = create_and_activate_template("async_job_poller", "E2E AsyncPoller", user, org)

    [
      run_test("Poller: complete_immediately → poll_count=1", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "job_type" => "transcoding",
            "input_url" => "https://example.com/video.mp4",
            "simulate_job_id" => "complete_immediately"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["job_status"], "completed", "job_status")
        assert_eq!(output["poll_count"], 1, "poll_count")
        assert_present!(output["result_url"], "result_url")
        :ok
      end),
      run_test("Poller: normal job → completes on poll 2", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "job_type" => "ml_inference",
            "input_url" => "https://example.com/data.json"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["job_status"], "completed", "job_status")
        assert_eq!(output["poll_count"], 2, "poll_count")
        :ok
      end),
      run_test("Poller: fail_on_poll → 422", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "job_type" => "report",
            "input_url" => "https://example.com/input.csv",
            "simulate_job_id" => "fail_on_poll"
          })

        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "failed", "error")
        :ok
      end),
      run_test("Poller: job_id stored in output", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "job_type" => "transcoding",
            "input_url" => "https://example.com/vid.mp4",
            "simulate_job_id" => "complete_immediately"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["job_id"], "complete_immediately", "job_id")
        :ok
      end),
      run_test("Poller: missing input_url → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"job_type" => "transcoding"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "complete_immediately → poll_count=1",
        input: %{
          "job_type" => "transcoding",
          "input_url" => "https://example.com/video.mp4",
          "simulate_job_id" => "complete_immediately"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["job_status"] == "completed" and
               output["poll_count"] == 1 do
            :ok
          else
            {:error, "expected job_status=completed + poll_count=1, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "normal job",
        input: %{
          "job_type" => "ml_inference",
          "input_url" => "https://example.com/data.json"
        },
        verify: fn resp ->
          if resp.status == 200, do: :ok, else: {:error, "expected 200, got #{resp.status}"}
        end
      },
      %{
        name: "missing input_url",
        input: %{"job_type" => "transcoding"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
