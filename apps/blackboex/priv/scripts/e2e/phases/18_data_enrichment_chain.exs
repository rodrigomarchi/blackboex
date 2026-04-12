defmodule E2E.Phase.DataEnrichmentChain do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 18: Data Enrichment Chain"))
    flow = create_and_activate_template("data_enrichment_chain", "E2E Enrichment", user, org)

    [
      run_test("Enrichment: primary source found", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"email" => "alice@co.com"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["source"], "primary", "source")
        assert_eq!(output["confidence"], 90, "confidence")
        assert_eq!(output["sources_tried"], 1, "sources_tried")
        :ok
      end),
      run_test("Enrichment: fallback source", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"email" => "fallback_user@co.com"})
        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["source"], "fallback", "source")
        assert_eq!(output["confidence"], 60, "confidence")
        assert_eq!(output["sources_tried"], 2, "sources_tried")
        :ok
      end),
      run_test("Enrichment: missing email → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"name" => "X"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "email found (primary source)",
        input: %{"email" => "alice@co.com"},
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["source"] == "primary" do
            :ok
          else
            {:error, "expected source=primary, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing email",
        input: %{"name" => "X"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
