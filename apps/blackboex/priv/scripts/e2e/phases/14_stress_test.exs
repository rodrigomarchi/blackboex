defmodule E2E.Phase.StressTest do
  import E2E.Helpers

  @stress_concurrency 50
  @stress_total 200

  def run(flow) do
    IO.puts(
      cyan(
        "\n▸ Phase 11: Stress Test (#{@stress_total} requests, #{@stress_concurrency} concurrent)"
      )
    )

    payloads = [
      %{"name" => "Stress Email", "email" => "stress@test.com"},
      %{"name" => "Stress Phone", "phone" => "11999000111"},
      %{"name" => "Stress NoContact"}
    ]

    IO.puts("  Firing #{@stress_total} requests...")

    start_time = System.monotonic_time(:millisecond)

    results =
      1..@stress_total
      |> Task.async_stream(
        fn i ->
          payload = Enum.at(payloads, rem(i, length(payloads)))
          {i, webhook_post(flow.webhook_token, payload)}
        end,
        max_concurrency: @stress_concurrency,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {_i, {:ok, resp}}} -> resp
        {:ok, {_i, {:error, reason}}} -> {:error, reason}
        {:exit, :timeout} -> {:error, :timeout}
      end)

    elapsed = System.monotonic_time(:millisecond) - start_time

    successes = Enum.count(results, &match?(%{status: 200}, &1))
    errors_422 = Enum.count(results, &match?(%{status: 422}, &1))
    errors_500 = Enum.count(results, &match?(%{status: 500}, &1))
    timeouts = Enum.count(results, &match?({:error, _}, &1))

    latencies =
      results
      |> Enum.filter(&match?(%{status: 200}, &1))
      |> Enum.map(& &1.body["duration_ms"])
      |> Enum.filter(&is_number/1)
      |> Enum.sort()

    rps = if elapsed > 0, do: Float.round(@stress_total / (elapsed / 1_000), 1), else: 0.0

    IO.puts("  Completed in #{elapsed}ms (#{rps} req/s)")

    IO.puts(
      "  200: #{successes} | 422: #{errors_422} | 500: #{errors_500} | timeout: #{timeouts}"
    )

    if length(latencies) > 0 do
      p50 = Enum.at(latencies, div(length(latencies), 2))
      p95 = Enum.at(latencies, trunc(length(latencies) * 0.95))
      p99 = Enum.at(latencies, min(trunc(length(latencies) * 0.99), length(latencies) - 1))
      max_lat = List.last(latencies)
      IO.puts("  Latency (execution_ms): p50=#{p50} p95=#{p95} p99=#{p99} max=#{max_lat}")
    end

    test_results = [
      run_test("Stress: all requests completed (no timeouts)", fn ->
        if timeouts > 0, do: raise("#{timeouts} requests timed out")
        :ok
      end),
      run_test("Stress: no 500 errors", fn ->
        if errors_500 > 0, do: raise("#{errors_500} requests returned HTTP 500")
        :ok
      end),
      run_test("Stress: all 200s returned valid output", fn ->
        bad =
          results
          |> Enum.filter(&match?(%{status: 200}, &1))
          |> Enum.reject(fn resp ->
            output = resp.body["output"]
            is_map(output) and (Map.has_key?(output, "channel") or Map.has_key?(output, "error"))
          end)

        if length(bad) > 0, do: raise("#{length(bad)} responses had invalid output")
        :ok
      end),
      run_test("Stress: throughput > 10 req/s", fn ->
        if rps < 10.0, do: raise("Only #{rps} req/s")
        :ok
      end)
    ]

    test_results
  end

  def stress_scenarios, do: []
end
