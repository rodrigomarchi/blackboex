defmodule Blackboex.Agent.FixPrompts do
  @moduledoc """
  Focused prompts for code correction steps in the hybrid pipeline.
  Each prompt is minimal — only the code and error context needed to fix the issue.
  """

  @spec fix_compilation(String.t(), String.t()) :: {String.t(), String.t()}
  def fix_compilation(code, errors) do
    system = """
    You are an expert Elixir developer. Fix compilation errors in the code below.
    Return ONLY the complete corrected code. No explanations, no markdown fences.
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
    The linter enforces: max 20 lines per function, max 3 nesting levels,
    @doc and @spec required on all public functions, @spec on private functions.
    Return ONLY the complete corrected code. No explanations, no markdown fences.
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
