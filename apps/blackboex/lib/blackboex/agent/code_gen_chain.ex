defmodule Blackboex.Agent.CodeGenChain do
  @moduledoc """
  Builds a LangChain LLMChain configured for initial API code generation.

  The agent has access to tools (compile, format, lint, generate_tests, run_tests,
  submit_code) and autonomously decides the order of operations. The chain runs
  until the agent calls `submit_code` or guardrails force termination.

  System prompt is composed from:
  - `Blackboex.LLM.Prompts.system_prompt()` — production-tested code rules, schemas, docs
  - `Blackboex.LLM.Templates.get/1` — concrete example per template type
  - Agent-specific tool/workflow instructions
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message

  alias Blackboex.Agent.{Callbacks, Tools}
  alias Blackboex.LLM.{Prompts, Templates}

  @max_runs 15

  @agent_instructions """
  ## Agent Tools

  You have access to the following tools. Use them to validate your code before submitting.

  - **compile_code**: Compiles your code. Returns 'Compiled successfully' or detailed errors with line numbers. Always compile before submitting.
  - **format_code**: Formats code with mix format. Always format before submitting.
  - **lint_code**: Runs Credo linter. Checks for long lines, missing @spec/@doc, function length, nesting depth. Fix any issues found.
  - **generate_tests**: Creates ExUnit test cases for your code via a secondary LLM call. Call after code compiles successfully.
  - **run_tests**: Runs tests against your code in a sandbox. Returns pass/fail details. If tests fail, analyze whether the bug is in the handler code or in the test itself.
  - **submit_code**: Submit your final code + tests + summary. Only call when everything compiles, is formatted, linted, and tests pass.

  ## Expected Workflow
  1. Generate the handler code following the rules and template above
  2. Call compile_code (fix errors if any — pay attention to validation messages)
  3. Call format_code
  4. Call lint_code (fix issues if any — especially missing @doc and @spec)
  5. Call generate_tests
  6. Call run_tests (fix failures if any — the bug may be in your code OR in the generated test)
  7. Call submit_code with your final code, tests, and a 2-3 sentence summary

  ## Important
  - The compile_code tool validates security constraints (no forbidden modules, no conn usage, etc.) and compiles the full module. Read error messages carefully.
  - If compilation fails with "handler must return a plain map", you are using conn/json/put_status — remove them.
  - If compilation fails with "only Request, Response, Params are allowed", you defined a disallowed defmodule — rename or remove it.
  - Keep functions short (max 20 lines) and nesting shallow (max 3 levels).
  - Handle edge cases: nil inputs, empty strings, invalid types.
  """

  @spec build(String.t(), keyword()) :: LLMChain.t()
  def build(description, opts \\ []) do
    llm = build_llm(opts)
    context = Keyword.get(opts, :context, %{})
    session_ctx = Keyword.get(opts, :session_ctx)

    template_type = extract_template_type(context)
    system = build_system_prompt(template_type)

    chain =
      %{llm: llm, verbose: false, custom_context: context}
      |> LLMChain.new!()
      |> LLMChain.add_tools(Tools.all_tools())
      |> LLMChain.add_message(Message.new_system!(system))
      |> LLMChain.add_message(Message.new_user!(description))

    if session_ctx do
      LLMChain.add_callback(chain, Callbacks.build(session_ctx))
    else
      chain
    end
  end

  @spec run(LLMChain.t(), keyword()) ::
          {:ok, LLMChain.t(), term()} | {:error, LLMChain.t(), term()}
  def run(chain, opts \\ []) do
    max_runs = Keyword.get(opts, :max_runs, @max_runs)
    LLMChain.run_until_tool_used(chain, "submit_code", max_runs: max_runs)
  end

  @spec system_prompt() :: String.t()
  def system_prompt, do: build_system_prompt(:computation)

  defp build_system_prompt(template_type) do
    """
    #{Prompts.system_prompt()}

    #{Templates.get(template_type)}

    #{@agent_instructions}
    """
  end

  defp extract_template_type(context) do
    case get_in(context, [:api, Access.key(:template_type)]) do
      "crud" -> :crud
      "webhook" -> :webhook
      _ -> :computation
    end
  end

  defp build_llm(opts) do
    model = Keyword.get(opts, :model, "claude-sonnet-4-20250514")
    temperature = Keyword.get(opts, :temperature, 0.2)
    max_tokens = Keyword.get(opts, :max_tokens, 16_384)
    stream = Keyword.get(opts, :stream, true)

    ChatAnthropic.new!(%{
      model: model,
      temperature: temperature,
      max_tokens: max_tokens,
      stream: stream
    })
  end
end
