# E2E Flow Tests — Full Suite
#
# Runs against the local dev server (localhost:4000).
# Creates flows on the rodtroll@gmail.com account, activates them,
# fires webhook requests, validates outputs, and cleans up.
#
# Usage:
#   mix run apps/blackboex/priv/scripts/e2e_flows.exs
#   mix run apps/blackboex/priv/scripts/e2e_flows.exs -- --stress
#   mix run apps/blackboex/priv/scripts/e2e_flows.exs -- --full-stress [--requests N] [--concurrency C]
#
# Prerequisites:
#   - `make server` running in another terminal (normal mode)
#   - `make stress-server` running for --stress / --full-stress (disables code reloader)
#   - User rodtroll@gmail.com exists in the local DB

script_dir = __DIR__
Code.require_file("e2e/helpers.exs", script_dir)
Code.require_file("e2e/setup.exs", script_dir)

for path <- Path.wildcard(Path.join([script_dir, "e2e/phases/*.exs"])) |> Enum.sort() do
  Code.require_file(path)
end

defmodule E2E.Flows do
  import E2E.Helpers
  import E2E.Setup

  def run(argv \\ []) do
    opts = parse_opts(argv)
    mode = Keyword.get(opts, :mode, :normal)

    IO.puts(bold("\n══════════════════════════════════════════════"))

    case mode do
      :full_stress ->
        IO.puts(bold("  E2E Flow Tests — Full Parallel Stress Mode"))

      :stress ->
        IO.puts(bold("  E2E Flow Tests — Normal + Per-Flow Stress"))

      _ ->
        IO.puts(bold("  E2E Flow Tests — Full Suite"))
    end

    IO.puts(bold("══════════════════════════════════════════════\n"))

    if mode in [:stress, :full_stress] do
      IO.puts(
        IO.ANSI.yellow() <>
          "  ⚠  Stress mode requirements:\n" <>
          "     Server: make stress-server  (disables code reloader + raises fd limit)\n" <>
          "     Runner: make e2e.stress / make e2e.full-stress  (sets ulimit + env)\n" <>
          IO.ANSI.reset()
      )
    end

    with :ok <- check_server(),
         {:ok, user, org} <- setup_account(),
         :ok <- cleanup_previous_e2e(org) do
      results =
        case mode do
          :full_stress ->
            stress_opts = Keyword.take(opts, [:requests, :concurrency])
            E2E.Phase.StressSuite.run_full_parallel(user, org, stress_opts)

          :stress ->
            notif_flow =
              create_and_activate_template("notification", "E2E Notification", user, org)

            hw_flow = create_and_activate_template("hello_world", "E2E HelloWorld", user, org)
            normal_results = run_all_phases(user, org, notif_flow, hw_flow)
            stress_opts = Keyword.take(opts, [:requests, :concurrency])
            stress_results = E2E.Phase.StressSuite.run_per_flow(user, org, stress_opts)
            List.flatten([normal_results, stress_results])

          _ ->
            notif_flow =
              create_and_activate_template("notification", "E2E Notification", user, org)

            hw_flow = create_and_activate_template("hello_world", "E2E HelloWorld", user, org)
            run_all_phases(user, org, notif_flow, hw_flow)
        end

      report(results)
    else
      {:error, reason} ->
        IO.puts(red("✗ Setup failed: #{reason}"))
        System.halt(1)
    end
  end

  defp run_all_phases(user, org, notif_flow, hw_flow) do
    List.flatten([
      E2E.Phase.HelloWorld.run(hw_flow),
      E2E.Phase.Notification.run(notif_flow),
      E2E.Phase.AllNodesDemo.run(user, org, notif_flow),
      E2E.Phase.DataPipeline.run(user, org),
      E2E.Phase.OrderProcessor.run(user, org),
      E2E.Phase.BatchProcessor.run(user, org),
      E2E.Phase.HttpEnrichment.run(user, org),
      E2E.Phase.RestApiCrud.run(user, org),
      E2E.Phase.ApiStatusChecker.run(user, org),
      E2E.Phase.ApprovalWorkflow.run(user, org),
      E2E.Phase.AdvancedFeatures.run(user, org),
      E2E.Phase.LeadScoring.run(user, org),
      E2E.Phase.WebhookProcessor.run(user, org),
      E2E.Phase.SupportTicketRouter.run(user, org),
      E2E.Phase.EscalationApproval.run(user, org),
      E2E.Phase.DataEnrichmentChain.run(user, org),
      E2E.Phase.IncidentAlertPipeline.run(user, org),
      E2E.Phase.CustomerOnboarding.run(user, org),
      E2E.Phase.WebhookIdempotent.run(user, org),
      E2E.Phase.AbandonedCartRecovery.run(user, org),
      E2E.Phase.LlmRouter.run(user, org),
      E2E.Phase.ApprovalWithTimeout.run(user, org),
      E2E.Phase.SagaCompensation.run(user, org),
      E2E.Phase.NotificationFanout.run(user, org),
      E2E.Phase.SlaMonitor.run(user, org),
      E2E.Phase.AsyncJobPoller.run(user, org),
      E2E.Phase.GithubCiResponder.run(user, org),
      E2E.Phase.SubFlowOrchestrator.run(user, org),
      E2E.Phase.StressTest.run(hw_flow)
    ])
  end

  defp parse_opts(argv) do
    argv
    |> Enum.chunk_every(2, 1, [nil])
    |> Enum.reduce([], fn
      ["--full-stress", _], acc ->
        Keyword.put(acc, :mode, :full_stress)

      ["--stress", _], acc ->
        Keyword.put(acc, :mode, :stress)

      ["--requests", n], acc when is_binary(n) ->
        Keyword.put(acc, :requests, String.to_integer(n))

      ["--concurrency", n], acc when is_binary(n) ->
        Keyword.put(acc, :concurrency, String.to_integer(n))

      _, acc ->
        acc
    end)
  end
end

E2E.Flows.run(System.argv())
