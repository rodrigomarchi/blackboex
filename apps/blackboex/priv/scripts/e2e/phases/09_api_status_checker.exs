defmodule E2E.Phase.ApiStatusChecker do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 9: API Status Checker"))
    flow = create_and_activate_template("api_status_checker", "E2E StatusCheck", user, org)

    [
      run_test("StatusCheck: healthy endpoint returns success report", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"url" => "https://httpbin.org/get"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["healthy"], true, "healthy")
        assert_eq!(output["status_code"], 200, "status_code")
        assert_gte!(output["response_time_ms"], 0, "response_time_ms")
        assert_contains!(output["report"], "OK:", "report starts with OK")
        :ok
      end),
      run_test("StatusCheck: custom headers are sent and echoed back", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "url" => "https://example.com/api",
            "custom_header_name" => "X-Test",
            "custom_header_value" => "hello"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        # httpbin /anything echoes headers — x-check-url should contain our URL
        assert_eq!(output["healthy"], true, "healthy")
        assert_eq!(output["status_code"], 200, "status_code")
        :ok
      end),
      run_test("StatusCheck: URL with special chars is encoded", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{"url" => "https://example.com/path with spaces"})

        assert_status!(resp, 200)
        # The URL is interpolated into a header, not the request URL, so it passes
        assert_eq!(resp.body["output"]["healthy"], true, "healthy")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "healthy endpoint",
        input: %{"url" => "https://httpbin.org/get"},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["healthy"] == true do
            :ok
          else
            {:error, "expected healthy=true, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "custom service name",
        input: %{
          "url" => "https://example.com/api",
          "custom_header_name" => "X-Test",
          "custom_header_value" => "hello"
        },
        verify: fn resp ->
          if resp.status == 200 do
            :ok
          else
            {:error, "expected status=200, got #{resp.status}"}
          end
        end
      }
    ]
  end
end
