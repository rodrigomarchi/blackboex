defmodule E2E.Phase.BatchProcessor do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 6: Batch Processor (fetch API → for_each → aggregate)"))
    flow = create_and_activate_template("batch_processor", "E2E BatchProc", user, org)

    [
      run_test("Batch: fetch 5 posts and process each", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"limit" => 5})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["total_posts"], 5, "total_posts")
        assert_gte!(output["avg_words"], 1.0, "avg_words > 0")
        assert_present!(output["longest_title"], "longest_title not empty")
        :ok
      end),
      run_test("Batch: fetch 10 posts", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"limit" => 10})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["total_posts"], 10, "total_posts")
        assert_gte!(output["avg_words"], 1.0, "avg_words > 0")
        :ok
      end),
      run_test("Batch: default limit (no param)", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{})
        assert_status!(resp, 200)
        output = resp.body["output"]
        # Default limit is 5
        assert_eq!(output["total_posts"], 5, "total_posts default")
        :ok
      end),
      run_test("Batch: limit=1 single post", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"limit" => 1})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["total_posts"], 1, "total_posts")
        assert_present!(output["longest_title"], "has title")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "limit=5",
        input: %{"limit" => 5},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and is_integer(output["total_posts"]) and
               output["total_posts"] >= 1 do
            :ok
          else
            {:error, "expected total_posts >= 1, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "limit=1",
        input: %{"limit" => 1},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["total_posts"] == 1 do
            :ok
          else
            {:error, "expected total_posts=1, got #{inspect(output)}"}
          end
        end
      }
    ]
  end
end
