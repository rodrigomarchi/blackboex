# FlowAgent prompt quality gate.
#
# Runs each canonical prompt in test/fixtures/flow_agent_eval_prompts.json
# through `FlowAgent.DefinitionPipeline` using the REAL LLM client and
# validates:
#
#   1. The response contains a valid ~~~json fence (DefinitionParser passes).
#   2. The extracted map is a structurally valid BlackboexFlow (validate/1).
#   3. The extracted map can be parsed into a ParsedFlow (no cycles, single
#      start, no orphans).
#
# Shipping threshold: 9 of 10 prompts must pass. Anything below forces a
# prompt-engineering iteration before the feature is marked done.
#
# Usage:
#
#     cd apps/blackboex
#     mix run priv/scripts/flow_agent_eval.exs
#
# You can override the threshold with `FLOW_AGENT_EVAL_THRESHOLD=8` and the
# prompts file with `FLOW_AGENT_EVAL_PROMPTS=/some/other.json`.

alias Blackboex.FlowAgent.DefinitionPipeline
alias Blackboex.FlowExecutor.DefinitionParser, as: ParsedFlowParser

threshold =
  "FLOW_AGENT_EVAL_THRESHOLD"
  |> System.get_env("9")
  |> String.to_integer()

prompts_path =
  System.get_env("FLOW_AGENT_EVAL_PROMPTS") ||
    Path.expand("../../test/fixtures/flow_agent_eval_prompts.json", __DIR__)

prompts =
  prompts_path
  |> File.read!()
  |> Jason.decode!()

IO.puts("Running #{length(prompts)} FlowAgent eval prompts from #{prompts_path}")
IO.puts(String.duplicate("─", 60))

results =
  prompts
  |> Enum.with_index(1)
  |> Enum.map(fn {%{"id" => id, "message" => message}, idx} ->
    IO.write("  [#{idx}/#{length(prompts)}] #{id}… ")

    case DefinitionPipeline.run(:generate, message, nil, []) do
      {:ok, %{definition: definition}} ->
        case ParsedFlowParser.parse(definition) do
          {:ok, _parsed} ->
            IO.puts("✅")
            {:ok, id}

          {:error, reason} ->
            IO.puts("⚠️  parse failed: #{inspect(reason)}")
            {:error, id, {:parse, reason}}
        end

      {:error, reason} ->
        IO.puts("❌ #{inspect(reason)}")
        {:error, id, reason}
    end
  end)

passed = Enum.count(results, &match?({:ok, _}, &1))
failed = Enum.reject(results, &match?({:ok, _}, &1))

IO.puts(String.duplicate("─", 60))
IO.puts("Passed: #{passed}/#{length(prompts)}  (threshold: #{threshold})")

if failed != [] do
  IO.puts("\nFailures:")

  for {:error, id, reason} <- failed do
    IO.puts("  - #{id}: #{inspect(reason, limit: :infinity, pretty: true)}")
  end
end

if passed < threshold do
  IO.puts("\n❌ Quality gate FAILED — iterate the prompt before shipping.")
  System.halt(1)
else
  IO.puts("\n✅ Quality gate PASSED.")
end
