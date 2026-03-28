defmodule Blackboex.Agent.EditChain do
  @moduledoc """
  Builds a LangChain LLMChain configured for editing existing API code via chat.

  Includes previous run summaries for context and the current code/tests state.
  The agent modifies code, compiles, tests, and fixes issues autonomously.

  Reuses `Blackboex.LLM.Prompts.system_prompt()` for code rules, schemas, and
  documentation standards — the same production-tested prompt used in the original pipeline.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message

  alias Blackboex.Agent.{Callbacks, ContextBuilder, Tools}
  alias Blackboex.LLM.Prompts

  @max_runs 15

  @spec build(String.t(), keyword()) :: LLMChain.t()
  def build(instruction, opts \\ []) do
    llm = build_llm(opts)
    context = Keyword.get(opts, :context, %{})
    session_ctx = Keyword.get(opts, :session_ctx)

    current_code = Keyword.fetch!(opts, :current_code)
    current_tests = Keyword.get(opts, :current_tests, "")
    conversation_id = Keyword.get(opts, :conversation_id)

    previous_context =
      if conversation_id do
        ContextBuilder.build_previous_context(conversation_id)
      else
        ""
      end

    system_prompt = build_system_prompt(current_code, current_tests, previous_context)

    chain =
      %{llm: llm, verbose: false, custom_context: context}
      |> LLMChain.new!()
      |> LLMChain.add_tools(Tools.all_tools())
      |> LLMChain.add_message(Message.new_system!(system_prompt))
      |> LLMChain.add_message(Message.new_user!(instruction))

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

  defp build_system_prompt(current_code, current_tests, previous_context) do
    tests_section =
      if current_tests != "" do
        """

        ## Current Tests
        ```elixir
        #{current_tests}
        ```
        """
      else
        ""
      end

    previous_section =
      if previous_context != "" do
        "\n#{previous_context}\n"
      else
        ""
      end

    """
    You are an expert Elixir developer editing an existing API handler for the BlackBoex platform.
    The user will describe changes they want. Apply them carefully.
    #{previous_section}
    ## Current Code
    ```elixir
    #{current_code}
    ```
    #{tests_section}
    ## Edit Rules
    - Apply the requested changes to the code
    - After modifying, compile and test to ensure nothing broke
    - If existing tests fail after your changes, decide:
      - If test expectations are wrong (behavior intentionally changed): update the tests
      - If the code has a bug: fix the code
    - Generate new tests for new functionality
    - Keep all existing functionality working unless explicitly asked to remove it
    - Submit only when everything compiles, is formatted, linted, and tests pass
    - Before submitting, write a 2-3 sentence summary of what you changed and why

    #{Prompts.system_prompt()}

    ## Agent Tools

    You have access to the following tools. Use them to validate your code before submitting.

    - **compile_code**: Compiles your code. Returns 'Compiled successfully' or detailed errors with line numbers.
    - **format_code**: Formats code with mix format.
    - **lint_code**: Runs Credo linter. Fix any issues found.
    - **generate_tests**: Creates ExUnit test cases for your code.
    - **run_tests**: Runs tests against your code. If tests fail, analyze whether the bug is in your code or the test.
    - **submit_code**: Submit your final code + tests + summary. Only call when everything passes.

    ## Expected Workflow
    1. Modify the code according to the user's instruction
    2. Compile (fix errors if any)
    3. Format and lint
    4. Generate or update tests
    5. Run tests (fix failures)
    6. Submit final code + tests + summary
    """
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
