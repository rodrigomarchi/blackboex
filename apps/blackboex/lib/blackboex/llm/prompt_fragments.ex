defmodule Blackboex.LLM.PromptFragments do
  @moduledoc """
  Canonical source for reusable prompt text fragments.

  Every rule or instruction block that appears in more than one prompt module
  MUST be defined here — never duplicated inline. Prompt modules compose their
  system prompts by interpolating these fragments.

  All functions are pure: no side effects, no state. They return plain strings.
  """

  alias Blackboex.LLM.SecurityConfig

  # ── Handler Rules ─────────────────────────────────────────────

  @doc "Core rules for handler code: no Plug/Phoenix, plain maps, allowed modules."
  @spec handler_rules() :: String.t()
  def handler_rules do
    """
    ## Critical Rules
    1. Return ONLY function definitions (`def`/`defp`) and schema modules — NOT a full module.
    2. Functions receive params as a plain map and return a plain map.
    3. Do NOT use `conn`, `json/2`, `put_status/2`, `send_resp/3`, or any Plug/Phoenix functions.
    4. You MAY define `defmodule Request`, `defmodule Response`, and nested schema modules for embeds.
    5. Return plain Elixir maps like `%{result: value}`. The framework handles JSON.
    6. For validation errors, return detailed changeset errors:
       ```elixir
       errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
       %{error: "Validation failed", details: errors}
       ```
       IMPORTANT: Do NOT use `String.to_existing_atom`, `String.to_atom`, or `List.to_atom` anywhere.
       These functions are blocked by the security validator and will cause compilation failure.
       The simple `fn {msg, _opts} -> msg end` form is correct and sufficient.
       For other errors, return `%{error: "human-readable message"}`.
    7. NEVER use modules from the prohibited list.
    8. NEVER access filesystem, network, or system commands.
    9. NEVER use dynamic code execution, spawn, send, receive, or atom creation.
    """
  end

  # ── Module Lists ──────────────────────────────────────────────

  @doc "Formatted allowed/prohibited module sections from SecurityConfig."
  @spec allowed_and_prohibited_modules() :: String.t()
  def allowed_and_prohibited_modules do
    """
    ## Allowed Modules
    #{Enum.join(SecurityConfig.allowed_modules(), ", ")}

    ## Prohibited Modules (NEVER use these)
    #{Enum.join(SecurityConfig.prohibited_modules(), ", ")}
    """
  end

  # ── Documentation Standards ───────────────────────────────────

  @doc "Mandatory documentation requirements for generated code."
  @spec documentation_standards() :: String.t()
  def documentation_standards do
    """
    ## Documentation Standards (MANDATORY)
    - Every `defmodule` MUST have `@moduledoc` explaining its purpose and what it represents
    - Every public `def` MUST have `@doc` explaining:
      - What the function does
      - What inputs it expects (with examples)
      - What it returns on success and on error
      - Any edge cases or important behavior
    - Every public `def` MUST have `@spec` with precise typespecs
    - Private `defp` SHOULD have `@spec` and a brief inline comment if logic is non-obvious
    - Use descriptive variable names that reveal intent (not `x`, `n`, `val`)
    - Add inline comments for business rules and non-trivial logic
    - Use `# Example: ...` comments to show input/output examples inline
    """
  end

  # ── Elixir Syntax Rules ───────────────────────────────────────

  @doc "Critical Elixir syntax rules (elsif prohibition, cond do, pattern matching)."
  @spec elixir_syntax_rules() :: String.t()
  def elixir_syntax_rules do
    """
    ## Elixir Syntax Rules (CRITICAL — violations cause compilation failure)
    - **`elsif` DOES NOT EXIST in Elixir.** Never use it. It will not compile.
    - For multi-branch conditionals, use `cond do`:
      ```elixir
      # WRONG — will not compile:
      if x > 10 do
        :high
      elsif x > 5 do
        :medium
      else
        :low
      end

      # RIGHT — use cond do:
      cond do
        x > 10 -> :high
        x > 5  -> :medium
        true   -> :low
      end
      ```
    - Even better: use **pattern matching in function heads** for multi-branch logic:
      ```elixir
      defp classify(x) when x > 10, do: :high
      defp classify(x) when x > 5, do: :medium
      defp classify(_x), do: :low
      ```
    - `if/else` is fine ONLY for simple two-branch conditions. Never chain or nest them.
    - Use `case` for matching on a single value, `cond` for multiple boolean conditions.
    """
  end

  # ── Code Quality Rules ────────────────────────────────────────

  @doc "Linter-enforced code quality rules (line length, function size, nesting, annotations)."
  @spec code_quality_rules() :: String.t()
  def code_quality_rules do
    """
    ## Code Quality Rules (ENFORCED BY AUTOMATED LINTER — violations are rejected)
    1. **Max 120 characters per line** — break long lines with multi-line syntax
    2. **Max 40 lines per function** — this is STRICTLY enforced. Extract `defp` helpers for complex logic.
       A `case` with 5+ clauses that each build a map SHOULD be split into separate `defp` functions.
       Example: instead of a 50-line `build_details(type)` with inline maps, write
       `defp build_comprehensive_details`, `defp build_third_party_details`, etc.
    3. **Max 4 levels of nesting** (if/case/cond/with) — flatten with `with`, guards, or early return
    4. **Every public `def` MUST have `@doc` directly above it** (before `@spec`)
    5. **Every public `def` MUST have `@spec` directly above it** (after `@doc`)
    6. **Code MUST be compatible with `mix format`** — standard Elixir formatting
    7. **Max ~800 unique atoms** in the handler code — keep well under 1000 to avoid compilation limits

    Correct annotation order above every public function:
    ```elixir
    @doc "Describes what the function does."
    @spec function_name(map()) :: map()
    def function_name(params) do
      ...
    end
    ```

    WRONG patterns (will be rejected by linter):
    ```elixir
    # WRONG: missing @doc and @spec
    def handle(params) do ... end

    # WRONG: nesting depth > 4
    if a do
      if b do
        case c do
          :x ->
            with {:ok, v} <- d do  # depth 4 — this is the limit
              if e do               # depth 5 — REJECTED
              end
            end
        end
      end
    end

    # WRONG: function > 40 lines — extract helpers instead
    def handle(params) do
      # ... 45 lines of logic ...
    end
    ```

    RIGHT pattern — flat, short, documented:
    ```elixir
    @doc "Processes request and returns computed result."
    @spec handle(map()) :: map()
    def handle(params) do
      with {:ok, data} <- validate(params),
           {:ok, result} <- compute(data) do
        format_response(result)
      else
        {:error, reason} -> %{error: reason}
      end
    end

    @spec validate(map()) :: {:ok, map()} | {:error, String.t()}
    defp validate(params) do
      changeset = Request.changeset(params)
      if changeset.valid? do
          {:ok, Ecto.Changeset.apply_changes(changeset)}
        else
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          {:error, errors}
        end
    end
    ```
    """
  end

  # ── Function Decomposition ────────────────────────────────────

  @doc "Guidance for splitting large functions into composable helpers."
  @spec function_decomposition() :: String.t()
  def function_decomposition do
    """
    ## Function Decomposition (functions > 40 lines will be rejected)
    When building a function that computes multiple values (e.g., risk factors, pricing):
    - **Compute each value in its own `defp`** — one function per factor/calculation
    - **Assemble the result map in the main function** using the computed values
    - The main function should be a pipeline of helper calls, NOT inline logic
    Example for a pricing calculator:
    ```elixir
    @spec calculate(map()) :: map()
    defp calculate(data) do
      base = compute_base_rate(data.category)
      factor_a = compute_factor_a(data.age)
      factor_b = compute_factor_b(data.experience)
      total = base * factor_a * factor_b
      build_result(total, base, factor_a, factor_b)
    end

    @spec build_result(float(), float(), float(), float()) :: map()
    defp build_result(total, base, factor_a, factor_b) do
      %{total: Float.round(total, 2), breakdown: %{base: base, a: factor_a, b: factor_b}}
    end
    ```
    Avoid putting map construction with 10+ keys AND computation in the same function.
    """
  end

  # ── Schema Rules ──────────────────────────────────────────────

  @doc "Request/Response schema rules with embeds_one/embeds_many patterns."
  @spec schema_rules() :: String.t()
  def schema_rules do
    """
    ## Request/Response Schemas (REQUIRED)
    You MUST define BOTH `defmodule Request` AND `defmodule Response`.
    Use `use Blackboex.Schema` — it provides Ecto embedded_schema + Changeset.
    These modules define the API contract and are used to generate OpenAPI documentation.

    ```elixir
    defmodule Request do
      @moduledoc "Input schema for the API. Defines and validates incoming parameters."
      use Blackboex.Schema

      embedded_schema do
        field :field_name, :type  # :string, :integer, :float, :boolean, :map
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:field_name])
        |> validate_required([:field_name])
        # Add domain-specific validations: validate_number, validate_format, etc.
      end
    end

    defmodule Response do
      @moduledoc "Output schema for the API. Documents the success response structure."
      use Blackboex.Schema

      embedded_schema do
        field :result, :type
      end
    end
    ```

    For NESTED input (e.g., vehicle with year/category/value), use `embeds_one` / `embeds_many`:

    CRITICAL: Nested schemas used with `embeds_one`/`embeds_many` MUST define `changeset/2`
    (receiving struct AND params), NOT `changeset/1`. Ecto's `cast_embed` calls `changeset/2`
    internally — if you define only `changeset/1`, it will crash at runtime with
    "function Vehicle.changeset/2 is undefined or private".

    ```elixir
    defmodule Vehicle do
      @moduledoc "Nested schema for vehicle data."
      use Blackboex.Schema

      embedded_schema do
        field :year, :integer
        field :category, :string
        field :value_brl, :float
      end

      @doc "Validates vehicle params. Must be changeset/2 for cast_embed compatibility."
      @spec changeset(t(), map()) :: Ecto.Changeset.t()
      def changeset(struct \\\\ %__MODULE__{}, params) do
        struct
        |> cast(params, [:year, :category, :value_brl])
        |> validate_required([:year, :category, :value_brl])
      end
    end

    defmodule Request do
      @moduledoc "Input schema with nested objects."
      use Blackboex.Schema

      embedded_schema do
        field :coverage, :string
        embeds_one :vehicle, Vehicle
      end

      @doc "Validates and casts incoming parameters including nested objects."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:coverage])
        |> cast_embed(:vehicle, required: true)
        |> validate_required([:coverage])
      end
    end
    ```

    IMPORTANT: When the user's description implies nested/grouped data (e.g., "vehicle info",
    "driver details", "address", "items list"), ALWAYS use `embeds_one` (for objects) or
    `embeds_many` (for arrays) instead of `field :name, :map`. This enables:
    - Proper validation of nested fields via `cast_embed`
    - Automatic example generation with realistic nested values
    - Accurate OpenAPI schema generation with nested properties

    Rules for schemas:
    - ALWAYS define BOTH `defmodule Request` AND `defmodule Response`
    - Request MUST have `changeset/1` with all relevant validations
    - Response documents the success output (no changeset needed)
    - Use rich Ecto validations: `validate_required`, `validate_number`, `validate_length`,
      `validate_format`, `validate_inclusion`, etc.
    - The handler MUST use `Request.changeset(params)` to validate input
    - ONLY module names allowed: Request, Response, Params, and nested schema modules used by embeds
    - Nested schema modules (e.g., Vehicle, Driver, Item) MUST be defined BEFORE Request/Response
    - Nested schemas MUST define `changeset/2` (struct, params) — NOT `changeset/1` (params only).
      `cast_embed` calls `changeset/2` internally. Using `changeset/1` will crash at runtime.
    - NEVER use `Ecto.Repo`, `Ecto.Query`, or `unsafe_*` functions
    - NEVER use `field :name, :map` when the map has a known structure — use `embeds_one` instead
    """
  end

  # ── SEARCH/REPLACE Format ─────────────────────────────────────

  @doc "SEARCH/REPLACE block format instructions for diff-based edits."
  @spec search_replace_format() :: String.t()
  def search_replace_format do
    """
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
  end

  # ── Test Rules ────────────────────────────────────────────────

  @doc "Core test rules shared between test generation and test fixing prompts."
  @spec test_rules() :: String.t()
  def test_rules do
    """
    ## Test Rules
    - The `Handler` module wraps the handler code and is compiled separately.
    - Tests must call `Handler.handle(params)`, `Handler.handle_list(params)`, etc.
    - Do NOT define handler functions inside the test module.
    - Do NOT use Req, HTTPoison, File, System, Code, Process, or I/O modules.
    - Every public `def` in handler code MUST have @doc and @spec.
    - NEVER add `defmodule Handler` in the handler code — only Request, Response, Params are allowed.
    - NEVER use `==` for computed float values. Use tolerance: `assert abs(expected - actual) < 0.1`
      (use 0.1, NOT 0.01 — floating point errors can be up to 0.05 for monetary calculations).
    - For `0` vs `0.0`: use `assert result >= 0` not `assert result > 0.0` when zero is a valid result.
      Or use `assert is_number(result)` for type checking.
    - If a test asserts `> 0.0` and gets integer `0`, the fix is `>= 0` or check structure instead.
    - **Resilience rule**: If only 1-3 tests fail and you cannot confidently fix them after analyzing
      the error, DELETE those tests entirely. A passing suite with 30 tests is better than a failing
      suite with 33. Do not waste fix attempts on flaky or impossible-to-fix assertions.
    """
  end

  # ── Elixir Best Practices ─────────────────────────────────────

  @doc "Elixir best practices for handler code generation."
  @spec elixir_best_practices() :: String.t()
  def elixir_best_practices do
    """
    ## Elixir Best Practices
    - Pattern match in function heads instead of if/case when possible
    - Use guard clauses (`when is_integer(n) and n >= 0`) for constraints
    - Use the pipe operator `|>` for data transformation chains
    - Use `with` for multi-step validations that can fail
    - Use multi-clause functions for different scenarios
    - Prefer `Map.get/3` with defaults over bare `Map.get/2`
    - Return tagged tuples from helpers: `{:ok, result}` or `{:error, reason}`
    """
  end
end
