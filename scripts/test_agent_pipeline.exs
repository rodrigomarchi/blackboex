# Script to test the agent pipeline end-to-end with a real LLM.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-ant-... mix run scripts/test_agent_pipeline.exs
#
# Tests 4 code generation scenarios:
# 1. Simple addition API
# 2. API with parameter validation
# 3. Temperature conversion API
# 4. Existing API edit through chat

import Ecto.Query

alias Blackboex.{Apis, Apis.Api, Conversations, Repo}

defmodule TestHelper do
  @timeout 180_000
  @per_message_timeout 60_000

  def run_all(user_id, org_id) do
    IO.puts("\n========================================")
    IO.puts("  Agent Pipeline E2E Test")
    IO.puts("========================================\n")

    {results, api_ids} =
      [
        {1, "API simples de soma",
         description:
           "Create an API that receives two numbers 'a' and 'b' and returns their sum in a field called 'result'.",
         template: "computation"},
        {2, "API com validacao",
         description:
           "Create an API that receives a 'text' parameter and returns word_count and char_count. Validate that text is not empty.",
         template: "computation"},
        {3, "API de temperature converter",
         description:
           "Create an API that receives 'value' (number) and 'from' (celsius or fahrenheit) and converts the temperature. Return the converted value and the unit.",
         template: "computation"}
      ]
      |> Enum.reduce({[], []}, fn {num, name, opts}, {results, ids} ->
        {result, api_id} = test_case(num, name, org_id, user_id, opts)
        {[result | results], [api_id | ids]}
      end)

    {edit_result, edit_api_id} = test_edit(4, org_id, user_id)
    results = Enum.reverse([edit_result | results])
    api_ids = [edit_api_id | api_ids] |> Enum.reject(&is_nil/1)

    # Print results
    IO.puts("\n========================================")
    IO.puts("  RESULTS")
    IO.puts("========================================\n")

    Enum.each(results, fn {num, name, status, detail} ->
      icon = if status == :ok, do: "PASS", else: "FAIL"
      IO.puts("  [#{icon}] Test #{num}: #{name}")
      if status == :error, do: IO.puts("         #{detail}")
    end)

    failed = Enum.count(results, fn {_, _, s, _} -> s == :error end)
    passed = length(results) - failed
    IO.puts("\n  #{passed}/#{length(results)} passed, #{failed} failed\n")

    # Cleanup test APIs
    cleanup(api_ids)
  end

  def test_case(num, name, org_id, user_id, opts) do
    IO.puts("--- Test #{num}: #{name} ---")

    try do
      {:ok, api} =
        Apis.create_api(%{
          name: "test-#{num}-#{System.unique_integer([:positive])}",
          description: opts[:description],
          template_type: opts[:template],
          organization_id: org_id,
          user_id: user_id
        })

      IO.puts("  Created API: #{api.id}")

      # Subscribe BEFORE enqueuing
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "api:#{api.id}")

      {:ok, _} = Apis.start_agent_generation(api, opts[:description], user_id)
      IO.puts("  Enqueued generation job")

      run_id = wait_for_run_started(api.id)
      IO.puts("  Run started: #{run_id}")

      # Subscribe to run topic
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{run_id}")

      result = wait_for_completion(run_id)

      case result do
        {:ok, %{code: code, summary: summary}} ->
          IO.puts("  COMPLETED: #{summary}")
          IO.puts("  Code length: #{String.length(code || "")} chars")
          verify_db_state(api.id, org_id, run_id)
          {{num, name, :ok, summary}, api.id}

        {:error, error} ->
          IO.puts("  FAILED: #{error}")
          {{num, name, :error, error}, api.id}
      end
    rescue
      e ->
        msg = Exception.message(e)
        IO.puts("  EXCEPTION: #{msg}")
        {{num, name, :error, msg}, nil}
    end
  end

  def test_edit(num, org_id, user_id) do
    name = "Edit de API existente"
    IO.puts("--- Test #{num}: #{name} ---")

    try do
      {:ok, api} =
        Apis.create_api(%{
          name: "edit-test-#{System.unique_integer([:positive])}",
          description: "Calculator API",
          template_type: "computation",
          organization_id: org_id,
          user_id: user_id,
          source_code: """
          defmodule Handler do
            def handle(params) do
              a = Map.get(params, "a", 0)
              b = Map.get(params, "b", 0)
              %{result: a + b}
            end
          end
          """
        })

      IO.puts("  Created API with code: #{api.id}")

      Phoenix.PubSub.subscribe(Blackboex.PubSub, "api:#{api.id}")

      {:ok, _} =
        Apis.start_agent_edit(
          api,
          "Add a 'multiply' operation. When params has op='multiply', multiply a and b instead of adding.",
          user_id
        )

      IO.puts("  Enqueued edit job")

      run_id = wait_for_run_started(api.id)
      IO.puts("  Run started: #{run_id}")
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{run_id}")

      result = wait_for_completion(run_id)

      case result do
        {:ok, %{code: code, summary: summary}} ->
          has_multiply = code && String.contains?(code, "multiply")
          IO.puts("  COMPLETED: #{summary}")
          IO.puts("  Contains 'multiply': #{has_multiply}")
          verify_db_state(api.id, org_id, run_id)

          if has_multiply,
            do: {{num, name, :ok, summary}, api.id},
            else: {{num, name, :error, "Code does not contain 'multiply'"}, api.id}

        {:error, error} ->
          IO.puts("  FAILED: #{error}")
          {{num, name, :error, error}, api.id}
      end
    rescue
      e ->
        msg = Exception.message(e)
        IO.puts("  EXCEPTION: #{msg}")
        {{num, name, :error, msg}, nil}
    end
  end

  # ── Wait helpers ──────────────────────────────────────────────

  defp wait_for_run_started(api_id) do
    receive do
      {:agent_run_started, %{run_id: run_id}} ->
        run_id
    after
      30_000 ->
        raise "Timeout waiting for agent_run_started on api:#{api_id}"
    end
  end

  defp wait_for_completion(run_id) do
    # Guard against race condition: check DB first in case run already completed
    # before we subscribed to the run topic
    run = Blackboex.Conversations.get_run!(run_id)

    case run.status do
      s when s in ["completed", "partial"] ->
        IO.puts("  (run already #{s} in DB)")
        {:ok, %{code: run.final_code, summary: run.run_summary || s}}

      "failed" ->
        IO.puts("  (run already failed in DB)")
        {:error, run.error_summary || "Run failed"}

      _ ->
        wait_for_completion_loop(run_id, System.monotonic_time(:millisecond))
    end
  end

  defp wait_for_completion_loop(run_id, start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed > @timeout do
      # Last-resort: check DB
      run = Blackboex.Conversations.get_run!(run_id)

      case run.status do
        "completed" ->
          {:ok, %{code: run.final_code, summary: run.run_summary || "completed"}}

        "failed" ->
          {:error, run.error_summary || "Run failed"}

        other ->
          {:error, "Timeout after #{div(elapsed, 1000)}s (DB status: #{other})"}
      end
    else
      receive do
        {:agent_streaming, %{delta: _delta}} ->
          IO.write(".")
          wait_for_completion_loop(run_id, start_time)

        {:agent_action, %{tool: tool}} ->
          elapsed_s = div(System.monotonic_time(:millisecond) - start_time, 1000)
          IO.puts("\n  [#{elapsed_s}s] Tool: #{tool}")
          wait_for_completion_loop(run_id, start_time)

        {:tool_started, %{tool: _tool}} ->
          wait_for_completion_loop(run_id, start_time)

        {:tool_result, %{tool: tool, success: success, summary: summary}} ->
          icon = if success, do: "OK", else: "FAIL"
          IO.puts("  #{tool}: [#{icon}] #{String.slice(summary || "", 0, 200)}")
          wait_for_completion_loop(run_id, start_time)

        {:agent_message, _} ->
          wait_for_completion_loop(run_id, start_time)

        {:agent_started, _} ->
          wait_for_completion_loop(run_id, start_time)

        {:guardrail_triggered, %{type: type}} ->
          IO.puts("  Guardrail: #{type}")
          wait_for_completion_loop(run_id, start_time)

        {:agent_completed, %{code: code, summary: summary}} ->
          IO.puts("")
          {:ok, %{code: code, summary: summary}}

        {:agent_failed, %{error: error}} ->
          IO.puts("")
          {:error, error}
      after
        @per_message_timeout ->
          # Check DB before giving up — message may have been lost
          run = Blackboex.Conversations.get_run!(run_id)

          case run.status do
            "completed" ->
              IO.puts("\n  (recovered from DB — PubSub message lost)")
              {:ok, %{code: run.final_code, summary: run.run_summary || "completed"}}

            "failed" ->
              IO.puts("\n  (recovered from DB — PubSub message lost)")
              {:error, run.error_summary || "Run failed"}

            "partial" ->
              IO.puts("\n  (recovered from DB — partial completion)")
              {:ok, %{code: run.final_code, summary: run.run_summary || "partial"}}

            other ->
              elapsed_s = div(System.monotonic_time(:millisecond) - start_time, 1000)
              IO.puts("\n  [#{elapsed_s}s] No messages for #{div(@per_message_timeout, 1000)}s (status: #{other}), still waiting...")
              wait_for_completion_loop(run_id, start_time)
          end
      end
    end
  end

  # ── DB verification ───────────────────────────────────────────

  defp verify_db_state(api_id, org_id, run_id) do
    run = Blackboex.Conversations.get_run!(run_id)
    api = Blackboex.Apis.get_api(org_id, api_id)

    IO.puts("  DB Check:")
    IO.puts("    Run status: #{run.status}")
    IO.puts("    Run iterations: #{run.iteration_count}")
    IO.puts("    API source_code: #{String.length(api.source_code || "")} chars")
    IO.puts("    API test_code: #{String.length(api.test_code || "")} chars")
    IO.puts("    API generation_status: #{api.generation_status}")

    if run.status not in ["completed", "partial"] do
      IO.puts("    WARNING: Run status is #{run.status}, expected completed/partial")
    end

    if is_nil(api.source_code) or api.source_code == "" do
      IO.puts("    WARNING: API source_code is empty after completion!")
    end
  end

  # ── Cleanup ───────────────────────────────────────────────────

  defp cleanup(api_ids) do
    count = length(api_ids)

    if count > 0 do
      IO.puts("Cleaning up #{count} test APIs...")

      Enum.each(api_ids, fn id ->
        # Delete conversations/runs/events first (cascade should handle it, but be safe)
        import Ecto.Query
        Blackboex.Repo.delete_all(from(a in Blackboex.Apis.Api, where: a.id == ^id))
      end)

      IO.puts("Cleanup done.")
    end
  end
end

# ── Setup ────────────────────────────────────────────────────────────────

IO.puts("Setting up...\n")

# 1. Ensure Oban processes jobs
Oban.resume_queue(queue: :generation)
IO.puts("Oban :generation queue resumed")

# 2. Reset circuit breaker
Blackboex.LLM.CircuitBreaker.reset(:anthropic)
IO.puts("Circuit breaker reset for :anthropic")

# 3. Get admin user and org
user = Repo.get_by(Blackboex.Accounts.User, email: "admin@blackboex.com")

unless user do
  IO.puts("ERROR: No admin user found (admin@blackboex.com). Create one first.")
  System.halt(1)
end

org =
  Repo.one(
    from(o in Blackboex.Organizations.Organization,
      join: m in Blackboex.Organizations.Membership,
      on: m.organization_id == o.id,
      where: m.user_id == ^user.id,
      limit: 1
    )
  )

unless org do
  IO.puts("ERROR: User has no organization.")
  System.halt(1)
end

IO.puts("User: #{user.email} (#{user.id})")
IO.puts("Org: #{org.name} (#{org.id})")

# 4. Verify API key
key = Application.get_env(:langchain, :anthropic_key)

if is_nil(key) or key == "" do
  IO.puts("\nERROR: ANTHROPIC_API_KEY not set. Run with:")
  IO.puts("  ANTHROPIC_API_KEY=sk-ant-... mix run scripts/test_agent_pipeline.exs")
  System.halt(1)
end

IO.puts("API Key: #{String.slice(key, 0, 12)}...")

# 5. Check circuit breaker state
cb_state = Blackboex.LLM.CircuitBreaker.get_state(:anthropic)
IO.puts("Circuit breaker state: #{cb_state}")

# ── Run ──────────────────────────────────────────────────────────────────

TestHelper.run_all(user.id, org.id)

# Give Oban time to finish any remaining work
Process.sleep(2_000)
