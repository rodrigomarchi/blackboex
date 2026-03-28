defmodule Blackboex.Agent.CodeGenChain do
  @moduledoc """
  Builds a LangChain LLMChain configured for initial API code generation.

  The agent has access to tools (compile, format, lint, generate_tests, run_tests,
  submit_code) and autonomously decides the order of operations. The chain runs
  until the agent calls `submit_code` or guardrails force termination.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message

  alias Blackboex.Agent.{Callbacks, Tools}

  @max_runs 15

  @system_prompt """
  You are an expert Elixir developer building API handler modules for a platform called BlackBoex.

  ## Your Task
  Generate a handler module with Request/Response DTOs for the described API.
  After generating, you MUST compile, format, lint, test, and fix any issues before submitting.

  ## Available Tools
  - compile_code: Compiles your code. Returns errors with line numbers if it fails.
  - format_code: Formats code with mix format. Always format before submitting.
  - lint_code: Runs Credo linter. Fix any issues found.
  - generate_tests: Creates ExUnit test cases for your code. Call after code compiles.
  - run_tests: Runs tests against your code. Fix failures before submitting.
  - submit_code: Submit your final code + tests + summary. Only call when everything passes.

  ## Code Rules
  - Use ONLY: def, defp, defmodule, defstruct, @type, @spec, @enforce_keys
  - Define Request and Response structs with @enforce_keys and @type
  - Every public function MUST have @spec
  - FORBIDDEN: File I/O, System calls, Process spawning, :os, Port, Code.eval, Module.create, send, receive, apply
  - ALLOWED modules: Enum, Map, List, String, Integer, Float, Date, Time, DateTime, NaiveDateTime, Decimal, Jason, Regex, Kernel
  - Always compile before submitting
  - Always run tests before submitting
  - If tests fail, analyze WHY: the bug may be in the code OR in the test

  ## Expected Workflow
  1. Generate the handler module code
  2. Compile it (fix errors if any)
  3. Format it
  4. Lint it (fix issues if any)
  5. Generate tests
  6. Run tests (fix failures if any — could be code or test issue)
  7. Submit final code + tests + a 2-3 sentence summary

  ## Important
  - Write clean, idiomatic Elixir
  - Keep functions short and focused
  - Handle edge cases (nil inputs, empty lists, invalid data)
  - Before submitting, write a 2-3 sentence summary describing what you built
  """

  @spec build(String.t(), keyword()) :: LLMChain.t()
  def build(description, opts \\ []) do
    llm = build_llm(opts)
    context = Keyword.get(opts, :context, %{})
    session_ctx = Keyword.get(opts, :session_ctx)

    chain =
      %{llm: llm, verbose: false, custom_context: context}
      |> LLMChain.new!()
      |> LLMChain.add_tools(Tools.all_tools())
      |> LLMChain.add_message(Message.new_system!(@system_prompt))
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
  def system_prompt, do: @system_prompt

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
