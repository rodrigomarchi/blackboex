defmodule E2E.Phase.LlmRouter do
  import E2E.Helpers

  def run(user, org) do
    IO.puts(cyan("\n▸ Phase 23: LLM Router"))
    flow = create_and_activate_template("llm_router", "E2E LlmRouter", user, org)

    [
      run_test("LLM: analysis + high → high tier (opus)", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "prompt" => "Analyze this quarterly report",
            "task_type" => "analysis",
            "budget_tier" => "high"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["model_tier"], "high", "model_tier")
        assert_contains!(output["model_selected"], "opus", "model_selected")
        assert_present!(output["response"], "response")
        :ok
      end),
      run_test("LLM: generation + standard → standard tier", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "prompt" => "Write a product description",
            "task_type" => "generation",
            "budget_tier" => "standard"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["model_tier"], "standard", "model_tier")
        assert_contains!(resp.body["output"]["model_selected"], "sonnet", "model_selected")
        :ok
      end),
      run_test("LLM: classification + low → low tier (haiku)", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "prompt" => "Is this positive or negative?",
            "task_type" => "classification",
            "budget_tier" => "low"
          })

        assert_status!(resp, 200)
        output = resp.body["output"]
        assert_eq!(output["model_tier"], "low", "model_tier")
        assert_contains!(output["model_selected"], "haiku", "model_selected")
        :ok
      end),
      run_test("LLM: no budget_tier → standard tier", fn ->
        {:ok, resp} =
          webhook_post(flow.webhook_token, %{
            "prompt" => "Summarize this article",
            "task_type" => "summarization"
          })

        assert_status!(resp, 200)
        assert_eq!(resp.body["output"]["model_tier"], "standard", "model_tier")
        :ok
      end),
      run_test("LLM: missing prompt → 422", fn ->
        {:ok, resp} = webhook_post(flow.webhook_token, %{"task_type" => "generation"})
        assert_status!(resp, 422)
        assert_contains!(resp.body["error"], "Payload validation failed", "error")
        :ok
      end)
    ]
  end

  def stress_scenarios do
    [
      %{
        name: "analysis + high → high tier",
        input: %{
          "prompt" => "Analyze this quarterly report",
          "task_type" => "analysis",
          "budget_tier" => "high"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["model_tier"] == "high" do
            :ok
          else
            {:error, "expected model_tier=high, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "generation + standard → standard tier",
        input: %{
          "prompt" => "Write a product description",
          "task_type" => "generation",
          "budget_tier" => "standard"
        },
        verify: fn resp ->
          output = resp.body["output"]

          if resp.status == 200 and output["model_tier"] == "standard" do
            :ok
          else
            {:error, "expected model_tier=standard, got #{inspect(output)}"}
          end
        end
      },
      %{
        name: "missing prompt",
        input: %{"task_type" => "generation"},
        verify: fn resp ->
          if resp.status == 422, do: :ok, else: {:error, "expected 422, got #{resp.status}"}
        end
      }
    ]
  end
end
