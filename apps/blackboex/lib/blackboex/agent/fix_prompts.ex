defmodule Blackboex.Agent.FixPrompts do
  @moduledoc """
  Focused prompts for code correction steps in the hybrid pipeline.
  Each prompt is minimal — only the code and error context needed to fix the issue.
  """

  @spec fix_compilation(String.t(), String.t()) :: {String.t(), String.t()}
  def fix_compilation(code, errors) do
    system = """
    You are an expert Elixir developer. Fix compilation errors in the code below.

    CRITICAL CONSTRAINTS (handler code rules):
    - Return ONLY `def`/`defp` functions and `defmodule Request`/`defmodule Response` — NOT a full module.
    - Functions receive params as a plain map and return a plain map.
    - Do NOT use `conn`, `json/2`, `put_status/2`, `send_resp/3`, or any Plug/Phoenix functions.
    - Only allowed defmodule names: Request, Response, Params.
    - Every public `def` MUST have @doc and @spec directly above it.

    Common fixes:
    - "uses json()" → remove json(), return plain map instead: `%{result: value}`
    - "references conn" → remove conn parameter, receive params as plain map
    - "defines disallowed module" → rename to Request, Response, or Params; or inline the logic

    Return the complete corrected code in a single ```elixir code block.
    """

    prompt = """
    ## Compilation Errors
    #{errors}

    ## Code to Fix
    #{code}
    """

    {system, prompt}
  end

  @spec fix_lint(String.t(), String.t()) :: {String.t(), String.t()}
  def fix_lint(code, issues) do
    system = """
    You are an expert Elixir developer. Fix the linter issues in the code below.

    LINTER RULES (all enforced automatically):
    - Max 120 characters per line — break long lines
    - Max 20 lines per function — extract `defp` helpers
    - Max 3 levels of nesting (if/case/cond/with) — flatten with `with` or function clauses
    - Every public `def` MUST have @doc directly above it (before @spec)
    - Every public `def` MUST have @spec directly above it (after @doc)
    - Private `defp` SHOULD have @spec
    - Code MUST be compatible with `mix format`

    HOW TO FIX each issue type:

    "Missing @doc for function X" → Add @doc above @spec above def:
      @doc "Describes what X does."
      @spec x(map()) :: map()
      def x(params) do ...

    "Missing @spec for X/N" → Add @spec with correct arity:
      @spec x(map()) :: map()

    "Function X is too long (N lines, max 20)" → Extract logic into defp helpers:
      @spec validate(map()) :: {:ok, map()} | {:error, String.t()}
      defp validate(params) do ... end

    "Line N exceeds 120 characters" → Break into multiple lines or shorten

    "Deeply nested block at line N" → Refactor with `with` or pattern matching in function heads

    Return the complete corrected code in a single ```elixir code block.
    """

    prompt = """
    ## Lint Issues
    #{issues}

    ## Code to Fix
    #{code}
    """

    {system, prompt}
  end

  @spec fix_tests(String.t(), String.t(), String.t()) :: {String.t(), String.t()}
  def fix_tests(code, test_code, failures) do
    system = """
    You are an expert Elixir developer. Tests failed against the handler code.
    Analyze whether the bug is in the handler or in the test.
    Fix the appropriate code.

    IMPORTANT:
    - The `Handler` module wraps the handler code and is compiled separately.
    - Tests must call `Handler.handle(params)`, `Handler.handle_list(params)`, etc.
    - Do NOT define handler functions inside the test module.
    - Do NOT use Req, HTTPoison, File, System, Code, Process, or I/O modules.
    - Every public `def` in handler code MUST have @doc and @spec.

    Return in this EXACT format (no markdown fences):
    ---CODE---
    (complete handler code)
    ---TESTS---
    (complete test code)
    """

    prompt = """
    ## Test Failures
    #{failures}

    ## Handler Code
    #{code}

    ## Test Code
    #{test_code}
    """

    {system, prompt}
  end

  @spec edit_code(String.t(), String.t(), String.t(), String.t()) :: {String.t(), String.t()}
  def edit_code(base_system_prompt, instruction, current_code, current_tests) do
    system = """
    #{base_system_prompt}

    You are modifying existing code based on the user's instruction.
    Return ONLY the complete modified code. No explanations, no markdown fences.
    Preserve all existing functionality unless the instruction explicitly asks to change it.
    """

    prompt = """
    ## Instruction
    #{instruction}

    ## Current Code
    #{current_code}

    ## Current Tests
    #{current_tests}
    """

    {system, prompt}
  end

  @doc "Parse the ---CODE--- / ---TESTS--- format from test fix responses."
  @spec parse_code_and_tests(String.t()) :: {String.t(), String.t()} | :error
  def parse_code_and_tests(response) do
    case Regex.run(~r/---CODE---\s*\n(.*?)---TESTS---\s*\n(.*)/s, response) do
      [_, code, tests] -> {String.trim(code), String.trim(tests)}
      nil -> :error
    end
  end
end
