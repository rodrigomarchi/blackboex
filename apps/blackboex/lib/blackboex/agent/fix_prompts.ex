defmodule Blackboex.Agent.FixPrompts do
  @moduledoc """
  Focused prompts for code correction steps in the hybrid pipeline.
  Fix prompts use SEARCH/REPLACE edit format for efficiency — the LLM returns only
  the targeted changes instead of regenerating the entire code. Falls back to full
  code regeneration when edits can't be applied.
  """

  @edit_format_instructions """
  ## Response Format: SEARCH/REPLACE Edits

  Return ONLY targeted edits using this exact format (one or more blocks):

  <<<<<<< SEARCH
  (exact lines from the current code that need to change)
  =======
  (replacement lines)
  >>>>>>> REPLACE

  Rules:
  - The SEARCH block must match EXACTLY a contiguous section of the current code.
  - Include enough surrounding context lines (2-3) so the match is unique.
  - You can have multiple SEARCH/REPLACE blocks for multiple changes.
  - To ADD code (e.g., @doc above a function), use a SEARCH block that matches the
    existing lines and a REPLACE block that includes the new lines plus the original.
  - To DELETE code, use an empty REPLACE block.
  - NEVER return the full code. Only return the SEARCH/REPLACE blocks.
  """

  @spec fix_compilation(String.t(), String.t(), String.t()) :: {String.t(), String.t()}
  def fix_compilation(code, errors, context_log \\ "") do
    system = """
    You are an expert Elixir developer. Fix compilation errors using targeted edits.

    CRITICAL CONSTRAINTS (handler code rules):
    - Return ONLY `def`/`defp` functions and `defmodule Request`/`defmodule Response` — NOT a full module.
    - Functions receive params as a plain map and return a plain map.
    - Do NOT use `conn`, `json/2`, `put_status/2`, `send_resp/3`, or any Plug/Phoenix functions.
    - Allowed defmodule names: Request, Response, Params, and nested schema modules for embeds.
    - Every public `def` MUST have @doc and @spec directly above it.

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

    #{@edit_format_instructions}
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

    LINTER RULES (all enforced automatically):
    - Max 120 characters per line — break long lines
    - Max 40 lines per function — extract `defp` helpers for complex logic
    - Max 4 levels of nesting (if/case/cond/with) — flatten with `with` or function clauses
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

    "Function X is too long (N lines, max 40)" → Extract logic into defp helpers:
      @spec validate(map()) :: {:ok, map()} | {:error, String.t()}
      defp validate(params) do ... end

    "Line N exceeds 120 characters" → Break into multiple lines or shorten

    "Deeply nested block at line N" → Refactor with `with` or pattern matching in function heads

    IMPORTANT: When splitting functions, keep total unique atoms under 800 to avoid compilation limits.

    #{@edit_format_instructions}
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

    IMPORTANT:
    - The `Handler` module wraps the handler code and is compiled separately.
    - Tests must call `Handler.handle(params)`, `Handler.handle_list(params)`, etc.
    - Do NOT define handler functions inside the test module.
    - Do NOT use Req, HTTPoison, File, System, Code, Process, or I/O modules.
    - Every public `def` in handler code MUST have @doc and @spec.
    - NEVER add `defmodule Handler` in the handler code — only Request, Response, Params are allowed.
    - Prefer fixing the TESTS over the handler code. Only change the handler if the logic is truly wrong.
    - NEVER use `==` for computed float values. Use tolerance: `assert abs(expected - actual) < 0.1`
      (use 0.1, NOT 0.01 — floating point errors can be up to 0.05 for monetary calculations).
    - For `0` vs `0.0`: use `assert result >= 0` not `assert result > 0.0` when zero is a valid result.
      Or use `assert is_number(result)` for type checking.
    - If a test asserts `> 0.0` and gets integer `0`, the fix is `>= 0` or check structure instead.
    - **Resilience rule**: If only 1-3 tests fail and you cannot confidently fix them after analyzing
      the error, DELETE those tests entirely. A passing suite with 30 tests is better than a failing
      suite with 33. Do not waste fix attempts on flaky or impossible-to-fix assertions.

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

  # ── Parsers ────────────────────────────────────────────────────

  @doc "Parse SEARCH/REPLACE blocks from LLM response into structured edits."
  @spec parse_search_replace_blocks(String.t()) :: [%{search: String.t(), replace: String.t()}]
  def parse_search_replace_blocks(response) do
    # Normalize Windows line endings (\r\n) to Unix (\n) before parsing.
    # LLMs can return either format depending on training data.
    normalized = String.replace(response, "\r\n", "\n")

    ~r/<<<<<<< SEARCH\n(.*?)=======\n(.*?)>>>>>>> REPLACE/s
    |> Regex.scan(normalized)
    |> Enum.map(fn [_, search, replace] ->
      %{search: String.trim_trailing(search, "\n"), replace: String.trim_trailing(replace, "\n")}
    end)
  end

  @doc "Parse the ---CODE--- / ---TESTS--- format with SEARCH/REPLACE blocks."
  @spec parse_test_fix_edits(String.t()) ::
          {[%{search: String.t(), replace: String.t()}],
           [%{search: String.t(), replace: String.t()}]}
          | :error
  def parse_test_fix_edits(response) do
    code_section =
      case Regex.run(~r/---CODE---\s*\n(.*?)(?=---TESTS---|$)/s, response) do
        [_, section] -> parse_search_replace_blocks(section)
        nil -> []
      end

    test_section =
      case Regex.run(~r/---TESTS---\s*\n(.*)/s, response) do
        [_, section] -> parse_search_replace_blocks(section)
        nil -> []
      end

    if code_section == [] and test_section == [] do
      :error
    else
      {code_section, test_section}
    end
  end

  @doc "Parse the ---CODE--- / ---TESTS--- format from test fix responses (legacy full-code format)."
  @spec parse_code_and_tests(String.t()) :: {String.t(), String.t()} | :error
  def parse_code_and_tests(response) do
    case Regex.run(~r/---CODE---\s*\n(.*?)---TESTS---\s*\n(.*)/s, response) do
      [_, code, tests] -> {String.trim(code), String.trim(tests)}
      nil -> :error
    end
  end

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
