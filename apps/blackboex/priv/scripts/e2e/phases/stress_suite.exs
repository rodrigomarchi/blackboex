defmodule E2E.Phase.StressSuite do
  @moduledoc """
  Parallel stress suite — runs all template flows under concurrent load simultaneously.

  Usage via e2e_flows.exs:
    mix run ... -- --full-stress [--requests N] [--concurrency C]

  Defaults: 50 requests per flow, 10 concurrent per flow.
  """

  import E2E.Helpers

  # List of {module, template_id, name} — phases with empty stress_scenarios are excluded
  @phases [
    {E2E.Phase.HelloWorld, "hello_world", "HelloWorld"},
    {E2E.Phase.Notification, "notification", "Notification"},
    {E2E.Phase.DataPipeline, "data_pipeline", "DataPipeline"},
    {E2E.Phase.OrderProcessor, "order_processor", "OrderProcessor"},
    {E2E.Phase.BatchProcessor, "batch_processor", "BatchProcessor"},
    {E2E.Phase.HttpEnrichment, "http_enrichment", "HttpEnrichment"},
    {E2E.Phase.RestApiCrud, "rest_api_crud", "RestApiCrud"},
    {E2E.Phase.ApiStatusChecker, "api_status_checker", "ApiStatusChecker"},
    {E2E.Phase.ApprovalWorkflow, "approval_workflow", "ApprovalWorkflow"},
    {E2E.Phase.AdvancedFeatures, "advanced_features", "AdvancedFeatures"},
    {E2E.Phase.LeadScoring, "lead_scoring", "LeadScoring"},
    {E2E.Phase.WebhookProcessor, "webhook_processor", "WebhookProcessor"},
    {E2E.Phase.SupportTicketRouter, "support_ticket_router", "SupportTicketRouter"},
    {E2E.Phase.EscalationApproval, "escalation_approval", "EscalationApproval"},
    {E2E.Phase.DataEnrichmentChain, "data_enrichment_chain", "DataEnrichmentChain"},
    {E2E.Phase.IncidentAlertPipeline, "incident_alert_pipeline", "IncidentAlertPipeline"},
    {E2E.Phase.CustomerOnboarding, "customer_onboarding", "CustomerOnboarding"},
    {E2E.Phase.WebhookIdempotent, "webhook_idempotent", "WebhookIdempotent"},
    {E2E.Phase.AbandonedCartRecovery, "abandoned_cart_recovery", "AbandonedCartRecovery"},
    {E2E.Phase.LlmRouter, "llm_router", "LlmRouter"},
    {E2E.Phase.ApprovalWithTimeout, "approval_with_timeout", "ApprovalWithTimeout"},
    {E2E.Phase.SagaCompensation, "saga_compensation", "SagaCompensation"},
    {E2E.Phase.NotificationFanout, "notification_fanout", "NotificationFanout"},
    {E2E.Phase.SlaMonitor, "sla_monitor", "SlaMonitor"},
    {E2E.Phase.AsyncJobPoller, "async_job_poller", "AsyncJobPoller"},
    {E2E.Phase.GithubCiResponder, "github_ci_responder", "GithubCiResponder"},
    {E2E.Phase.SubFlowOrchestrator, "sub_flow_orchestrator", "SubFlowOrchestrator"}
  ]

  @doc """
  Run per-flow stress tests sequentially (--stress mode).
  Each flow gets `requests` requests at `concurrency` concurrent.
  """
  def run_per_flow(user, org, opts \\ []) do
    :ok = start_stress_pool()
    requests = Keyword.get(opts, :requests, 30)
    concurrency = Keyword.get(opts, :concurrency, 10)

    IO.puts(
      cyan("\n▸ Per-Flow Stress Tests (#{requests} req × #{concurrency} concurrent per flow)")
    )

    @phases
    |> Enum.flat_map(fn {mod, template_id, name} ->
      scenarios = mod.stress_scenarios()

      if scenarios == [] do
        IO.puts(yellow("  ⊘ #{name}: skipped (no scenarios)"))
        []
      else
        flow = create_and_activate_template(template_id, "E2E Stress #{name}", user, org)
        [stress_flow(name, mod, flow.webhook_token, requests, concurrency)]
      end
    end)
  end

  @doc """
  Run all flows under simultaneous parallel load (--full-stress mode).
  All flows fire concurrently — simulates real production load.
  """
  def run_full_parallel(user, org, opts \\ []) do
    :ok = start_stress_pool()
    requests = Keyword.get(opts, :requests, 50)
    concurrency = Keyword.get(opts, :concurrency, 10)
    total = length(@phases) * requests

    IO.puts(
      cyan(
        "\n▸ Full Parallel Stress — ALL #{length(@phases)} flows × #{requests} req × #{concurrency} concurrent"
      )
    )

    IO.puts(cyan("  Total requests: #{total} across #{length(@phases)} flows simultaneously\n"))

    # Step 1: Create all flows in parallel
    IO.puts("  Creating #{length(@phases)} flows in parallel...")

    flows =
      @phases
      |> Task.async_stream(
        fn {mod, template_id, name} ->
          scenarios = mod.stress_scenarios()

          if scenarios == [] do
            {name, mod, nil}
          else
            flow = create_and_activate_template(template_id, "E2E FullStress #{name}", user, org)
            {name, mod, flow.webhook_token}
          end
        end,
        max_concurrency: length(@phases),
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    IO.puts(green("  All flows created. Firing #{total} requests simultaneously...\n"))

    start_time = System.monotonic_time(:millisecond)

    # Step 2: Fire all flows simultaneously
    results =
      flows
      |> Enum.reject(fn {_name, _mod, token} -> is_nil(token) end)
      |> Task.async_stream(
        fn {name, mod, token} ->
          stress_flow(name, mod, token, requests, concurrency)
        end,
        max_concurrency: length(@phases),
        timeout: 120_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    elapsed_ms = System.monotonic_time(:millisecond) - start_time
    total_fired = length(flows |> Enum.reject(fn {_, _, t} -> is_nil(t) end)) * requests

    IO.puts(cyan("\n  Full stress complete in #{elapsed_ms}ms"))

    IO.puts(
      cyan("  Aggregate throughput: #{Float.round(total_fired / (elapsed_ms / 1000), 1)} req/s\n")
    )

    results
  end

  # Fires `count` requests to a single flow using its scenarios, returns a test result tuple
  defp stress_flow(name, mod, token, count, concurrency) do
    scenarios = mod.stress_scenarios()

    if scenarios == [] do
      IO.puts(yellow("  ⊘ #{name}: skipped (no scenarios)"))
      []
    else
      start_time = System.monotonic_time(:millisecond)
      scenario_count = length(scenarios)

      results =
        1..count
        |> Task.async_stream(
          fn _i ->
            scenario =
              Enum.at(scenarios, rem(:rand.uniform(scenario_count * 100), scenario_count))

            actual_input =
              if is_function(scenario.input, 0), do: scenario.input.(), else: scenario.input

            case webhook_post(token, actual_input, finch: E2E.StressFinch) do
              {:ok, resp} ->
                if is_map(resp.body) do
                  case scenario.verify.(resp) do
                    :ok -> :ok
                    {:error, reason} -> {:error, "[#{scenario.name}] #{reason}"}
                  end
                else
                  {:error, "[#{scenario.name}] server returned non-JSON: HTTP #{resp.status}"}
                end

              {:error, reason} ->
                {:error, inspect(reason)}
            end
          end,
          max_concurrency: concurrency,
          timeout: 30_000
        )
        |> Enum.map(fn
          {:ok, r} -> r
          {:exit, reason} -> {:error, inspect(reason)}
        end)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time
      successes = Enum.count(results, &(&1 == :ok))
      failures = Enum.count(results, &match?({:error, _}, &1))
      throughput = Float.round(count / (elapsed_ms / 1000), 1)
      success_rate = Float.round(successes / count * 100, 1)

      label = "Stress #{name}: #{successes}/#{count} ok (#{success_rate}%) @ #{throughput} req/s"

      run_test(label, fn ->
        if failures > 0 do
          errors =
            results
            |> Enum.filter(&match?({:error, _}, &1))
            |> Enum.take(3)
            |> Enum.map(fn {:error, r} -> r end)

          raise "#{failures} failures: #{Enum.join(errors, "; ")}"
        end

        if throughput < 2.0, do: raise("Throughput too low: #{throughput} req/s")
        :ok
      end)
    end
  end
end
