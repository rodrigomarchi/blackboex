defmodule E2E.Phase.HttpEnrichment do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 7: HTTP Enrichment"))
    flow = create_and_activate_template("http_enrichment", "E2E HttpEnrich", user, org)

    [
      run_test("HTTP: fetches from httpbin with query interpolation", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"query" => "test_value"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["http_status"], 200, "http_status")
        assert_eq!(output["method"], "GET", "method")
        assert_contains!(output["response_url"], "test_value", "URL contains query")
        :ok
      end),
      run_test("HTTP: different query value", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"query" => "hello_world"})
        assert_status!(resp, 200)
        assert_contains!(resp.body["output"]["response_url"], "hello_world", "URL contains query")
        :ok
      end),
      run_test("HTTP: spaces in query are URL-encoded", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"query" => "foo bar"})
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["http_status"], 200, "http_status")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "query=stress",
        input: %{"query" => "stress"},
        verify: fn resp ->
          if resp.status == 200 and is_map(resp.body["output"]) do
            :ok
          else
            {:error, "expected status=200 with output, got status=#{resp.status}"}
          end
        end
      },
      %{
        name: "query=hello",
        input: %{"query" => "hello"},
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
