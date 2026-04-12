defmodule E2E.Phase.DataPipeline do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 4: Data Pipeline"))
    flow = create_and_activate_template("data_pipeline", "E2E DataPipeline", user, org)

    [
      run_test("Pipeline: 3 records aggregated", fn ->
        records = [
          %{"name" => "A", "amount" => 100, "category" => "sales"},
          %{"name" => "B", "amount" => 50, "category" => "ops"},
          %{"name" => "C", "amount" => 30, "category" => "sales"}
        ]

        {:ok, resp} = webhook_post(flow.webhook_token, %{"records" => records})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["record_count"], 3, "record_count")
        assert_eq!(output["total_amount"], 180.0, "total_amount")
        assert_eq!(output["avg_amount"], 60.0, "avg_amount")
        :ok
      end),
      run_test("Pipeline: single record", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{"records" => [%{"name" => "X", "amount" => 42}]})

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["record_count"], 1, "record_count")
        assert_eq!(output["total_amount"], 42.0, "total_amount")
        assert_eq!(output["avg_amount"], 42.0, "avg_amount")
        :ok
      end),
      run_test("Pipeline: empty records", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"records" => []})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["record_count"], 0, "record_count")
        assert_eq!(output["total_amount"], 0.0, "total_amount")
        assert_eq!(output["avg_amount"], 0.0, "avg_amount")
        :ok
      end),
      run_test("Pipeline: missing amount defaults to 0", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"records" => [%{"name" => "NoAmt"}]})
        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["total_amount"], 0.0, "total_amount")
        :ok
      end),
      run_test("Pipeline: large batch (20 records)", fn ->
        records = Enum.map(1..20, fn i -> %{"name" => "R#{i}", "amount" => i * 10} end)
        {:ok, resp} = webhook_post(flow.webhook_token, %{"records" => records})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["record_count"], 20, "record_count")
        # sum of 10+20+...+200 = 10 * (1+2+...+20) = 10 * 210 = 2100
        assert_eq!(output["total_amount"], 2100.0, "total_amount")
        assert_eq!(output["avg_amount"], 105.0, "avg_amount")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "3 records aggregated",
        input: %{
          "records" => [
            %{"name" => "A", "amount" => 100, "category" => "sales"},
            %{"name" => "B", "amount" => 50, "category" => "ops"},
            %{"name" => "C", "amount" => 30, "category" => "sales"}
          ]
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["record_count"] == 3 and
               output["total_amount"] == 180.0 do
            :ok
          else
            {:error, "expected record_count=3, total_amount=180.0, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "single record",
        input: %{"records" => [%{"name" => "X", "amount" => 42}]},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["total_amount"] == 42.0 do
            :ok
          else
            {:error, "expected total_amount=42.0, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "empty records",
        input: %{"records" => []},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["record_count"] == 0 and
               output["total_amount"] == 0.0 do
            :ok
          else
            {:error, "expected record_count=0, total_amount=0.0, got #{inspect(output)}"}
          end
        end
      }
    ]
  end
end
