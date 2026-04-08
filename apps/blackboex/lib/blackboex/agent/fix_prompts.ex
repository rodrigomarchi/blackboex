defmodule Blackboex.Agent.FixPrompts do
  @moduledoc """
  Focused prompts for code correction steps in the hybrid pipeline.
  Fix prompts use SEARCH/REPLACE edit format for efficiency — the LLM returns only
  the targeted changes instead of regenerating the entire code. Falls back to full
  code regeneration when edits can't be applied.
  """

  alias Blackboex.LLM.PromptFragments
  alias Blackboex.LLM.PromptParsers

  @spec fix_compilation(String.t(), String.t(), String.t()) :: {String.t(), String.t()}
  def fix_compilation(code, errors, context_log \\ "") do
    system = """
    You are an expert Elixir developer. Fix compilation errors using targeted edits.

    #{PromptFragments.handler_rules()}
    #{PromptFragments.allowed_and_prohibited_modules()}

    Common fixes:
    - "uses json()" → remove json(), return plain map instead: `%{result: value}`
    - "references conn" → remove conn parameter, receive params as plain map
    - "defines disallowed module" → remove any `defmodule` except Request, Response, Params.
      Inline the logic or use `defp` helpers instead.
    - "elsif" or "missing terminator: end" near elsif → `elsif` DOES NOT EXIST in Elixir.
      Replace the entire if/elsif/else chain with `cond do`:
      WRONG: if x do ... elsif y do ... else ... end
      RIGHT: cond do
               x -> ...
               y -> ...
               true -> ...
             end
      Or even better, use pattern matching with multiple function clauses and guard clauses.
    - "changeset/2 is undefined" → Nested schemas used with embeds_one/embeds_many MUST
      define `changeset/2` (struct + params), NOT `changeset/1`. Fix:
      `def changeset(struct \\\\ %__MODULE__{}, params)` instead of `def changeset(params)`.
    - "too many unique atoms" → reduce code size: extract repeated map keys, merge
      similar functions, remove redundant default clauses. Keep total atoms well under 800.
    - "blocked function: String.to_existing_atom" or "String.to_atom" or "List.to_atom" →
      These functions are BLOCKED by the security validator. NEVER replace one with another.
      For `traverse_errors`, use the simple form: `fn {msg, _opts} -> msg end`.
      For any other atom conversion need, use a Map lookup or pattern matching instead.
      WRONG: `String.to_existing_atom(key)`, `String.to_atom(key)`, `List.to_atom(chars)`
      RIGHT: `fn {msg, _opts} -> msg end` (for traverse_errors)
      RIGHT: Use a map like `%{"key" => :key}` for known string-to-atom mappings

    #{PromptFragments.search_replace_format()}
    """

    context_section = build_context_section(context_log)

    prompt = """
    #{context_section}## Compilation Errors
    #{errors}

    ## Code to Fix
    #{code}
    """

    {system, prompt}
  end

  @spec fix_lint(String.t(), String.t(), String.t()) :: {String.t(), String.t()}
  def fix_lint(code, issues, context_log \\ "") do
    system = """
    You are an expert Elixir developer. Fix linter issues using targeted edits.

    #{PromptFragments.handler_rules()}
    #{PromptFragments.allowed_and_prohibited_modules()}
    #{PromptFragments.code_quality_rules()}

    HOW TO FIX each issue type:

    "Missing @doc for function X" → Add @doc above @spec above def:
      @doc "Describes what X does."
      @spec x(map()) :: map()
      def x(params) do ...

    "Missing @spec for X/N" → Add @spec with correct arity:
      @spec x(map()) :: map()

    "Function X is too long (N lines, max 40)" → Extract logic into defp helpers:
      @spec validate(map()) :: {:ok, map()} | {:error, String.t()}
      defp validate(params) do ... end

    "Line N exceeds 120 characters" → Break into multiple lines or shorten

    "Deeply nested block at line N" → Refactor with `with` or pattern matching in function heads

    IMPORTANT: When splitting functions, keep total unique atoms under 800 to avoid compilation limits.

    #{PromptFragments.search_replace_format()}
    """

    context_section = build_context_section(context_log)

    prompt = """
    #{context_section}## Lint Issues
    #{issues}

    ## Code to Fix
    #{code}
    """

    {system, prompt}
  end

  @spec fix_tests(String.t(), String.t(), String.t(), String.t()) :: {String.t(), String.t()}
  def fix_tests(code, test_code, failures, context_log \\ "") do
    system = """
    You are an expert Elixir developer. Tests failed against the handler code.
    Analyze whether the bug is in the handler or in the test.
    Fix the appropriate code using targeted edits.

    #{PromptFragments.handler_rules()}
    #{PromptFragments.allowed_and_prohibited_modules()}
    #{PromptFragments.test_rules()}

    - Prefer fixing the TESTS over the handler code. Only change the handler if the logic is truly wrong.

    ## Response Format

    Return edits in this format. Use ---CODE--- section ONLY if handler code needs changes,
    ---TESTS--- section ONLY if test code needs changes. Include both only if both need changes.

    If changing HANDLER code, use SEARCH/REPLACE blocks under ---CODE---:
    ---CODE---
    <<<<<<< SEARCH
    (exact lines to find in handler)
    =======
    (replacement)
    >>>>>>> REPLACE

    If changing TEST code, use SEARCH/REPLACE blocks under ---TESTS---:
    ---TESTS---
    <<<<<<< SEARCH
    (exact lines to find in tests)
    =======
    (replacement)
    >>>>>>> REPLACE
    """

    context_section = build_context_section(context_log)

    prompt = """
    #{context_section}## Test Failures
    #{failures}

    ## Handler Code
    #{code}

    ## Test Code
    #{test_code}
    """

    {system, prompt}
  end

  # ── Parsers (delegated to PromptParsers) ──────────────────────

  @doc "Parse SEARCH/REPLACE blocks from LLM response into structured edits."
  @spec parse_search_replace_blocks(String.t()) :: [%{search: String.t(), replace: String.t()}]
  defdelegate parse_search_replace_blocks(response), to: PromptParsers

  @doc "Parse the ---CODE--- / ---TESTS--- format with SEARCH/REPLACE blocks."
  @spec parse_test_fix_edits(String.t()) ::
          {[%{search: String.t(), replace: String.t()}],
           [%{search: String.t(), replace: String.t()}]}
          | :error
  defdelegate parse_test_fix_edits(response), to: PromptParsers

  @doc "Parse the ---CODE--- / ---TESTS--- format from test fix responses (legacy full-code format)."
  @spec parse_code_and_tests(String.t()) :: {String.t(), String.t()} | :error
  defdelegate parse_code_and_tests(response), to: PromptParsers

  # ── Private Helpers ────────────────────────────────────────────

  @spec build_context_section(String.t()) :: String.t()
  defp build_context_section(""), do: ""

  defp build_context_section(context_log) do
    """
    ## Pipeline History (what happened before this fix — do NOT repeat previous mistakes)
    #{context_log}

    """
  end
end
