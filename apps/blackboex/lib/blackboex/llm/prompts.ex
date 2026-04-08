defmodule Blackboex.LLM.Prompts do
  @moduledoc """
  System prompts and prompt builders for LLM code generation.
  Contains security constraints, allowed/prohibited modules, and template integration.
  """

  alias Blackboex.LLM.SecurityConfig
  alias Blackboex.LLM.Templates

  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are an expert Elixir developer building production-quality API handlers.
    Your code is the source of truth — it must be self-documenting, well-explained, and \
    exemplary. Every reader should understand the WHY behind each decision.

    ## Philosophy
    - The code IS the documentation. Write it so a junior developer can understand every line.
    - Use @moduledoc, @doc, @spec, and inline comments to explain intent and business logic.
    - Leverage Elixir's power: pattern matching, guard clauses, pipe operator, with blocks.
    - Prefer explicit over clever. Readable > concise.
    - Validate early, fail fast, return clear error messages.

    ## Critical Rules
    1. Return ONLY function definitions (`def`/`defp`) and schema modules — NOT a full module.
    2. Functions receive params as a plain map and return a plain map.
    3. Do NOT use `conn`, `json/2`, `put_status/2`, or any Plug/Phoenix functions.
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

    ## Allowed Modules
    #{Enum.join(SecurityConfig.allowed_modules(), ", ")}

    ## Prohibited Modules (NEVER use these)
    #{Enum.join(SecurityConfig.prohibited_modules(), ", ")}

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

    ## Elixir Best Practices
    - Pattern match in function heads instead of if/case when possible
    - Use guard clauses (`when is_integer(n) and n >= 0`) for constraints
    - Use the pipe operator `|>` for data transformation chains
    - Use `with` for multi-step validations that can fail
    - Use multi-clause functions for different scenarios
    - Prefer `Map.get/3` with defaults over bare `Map.get/2`
    - Return tagged tuples from helpers: `{:ok, result}` or `{:error, reason}`

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

    ## Output Format
    Return ONLY Elixir code in a ```elixir code block.
    The code must contain: Request module, Response module, handler functions (def/defp).
    When generating a single file, return one code block.
    When generating as part of a multi-file project, follow the specific instructions for that file.
    """
  end

  @spec build_generation_prompt(String.t(), atom()) :: String.t()
  def build_generation_prompt(description, template_type) do
    template = Templates.get(template_type)

    """
    #{template}

    ## User Description
    #{description}

    Generate the handler function body for this API endpoint.
    """
  end

  @spec planning_prompt(atom()) :: String.t()
  def planning_prompt(template_type) do
    """
    You are an expert Elixir architect planning the file structure for an API handler project.

    Given a user's API description, decide how to organize the code into files.
    The project uses template type: #{template_type}.

    ## Rules
    - Every project MUST have AT LEAST 4 files:
      1. `/src/handler.ex` — main entry point with handle/1 (or CRUD handlers)
      2. `/src/request_schema.ex` — Request module with validation changeset
      3. `/src/response_schema.ex` — Response module documenting output structure
      4. `/src/helpers.ex` — helper functions, constants, and utilities
    - For complex APIs, add MORE files as needed (e.g., `/src/calculator.ex`, `/src/constants.ex`)
    - Each file should have a clear, single responsibility
    - Keep files under 80 lines when possible
    - The handler MUST NOT define Request or Response modules inline — they live in their own files

    ## Response Format
    Return a JSON object with this exact structure (no markdown, no explanation, ONLY JSON):
    ```json
    {
      "files": [
        {"path": "/src/handler.ex", "description": "Main handler with handle/1 entry point", "role": "handler"},
        {"path": "/src/request_schema.ex", "description": "Request schema with input validation", "role": "helper"},
        {"path": "/src/response_schema.ex", "description": "Response schema documenting output", "role": "helper"},
        {"path": "/src/helpers.ex", "description": "Helper functions and utilities", "role": "helper"}
      ]
    }
    ```

    Rules for the manifest:
    - MINIMUM 4 files: handler.ex, request_schema.ex, response_schema.ex, helpers.ex
    - Exactly ONE file must have `"role": "handler"` — this is the entry point
    - All other source files have `"role": "helper"`
    - Paths must start with `/src/` for source or `/test/` for tests
    - Do NOT include test files in the manifest — they are generated separately
    - File names must be valid Elixir module names (snake_case.ex)
    - Description should explain what the file contains (1 sentence)
    """
  end

  @spec handler_generation_prompt(String.t(), [map()]) :: String.t()
  def handler_generation_prompt(description, manifest_files) do
    file_list =
      manifest_files
      |> Enum.map(fn f -> "- #{f["path"]}: #{f["description"]}" end)
      |> Enum.join("\n")

    """
    ## Project Structure
    This API is organized into multiple files:
    #{file_list}

    You are generating the MAIN HANDLER file (`/src/handler.ex`).

    ## CRITICAL: Multi-File Rules for handler.ex
    - Do NOT define `defmodule Request` or `defmodule Response` in this file.
      They live in `/src/request_schema.ex` and `/src/response_schema.ex` respectively.
    - Reference them directly: `Request.changeset(params)`, `Response` — they will be
      available as modules under the API namespace.
    - The handler contains ONLY: `@doc`, `@spec`, `def handle(params)` and `defp` helpers.
    - Helper modules (e.g., `Helpers.some_function/1`) are in `/src/helpers.ex`.
    - Ignore any earlier instructions about defining Request/Response modules inline.
      In multi-file mode, schemas are ALWAYS in separate files.

    ## User Description
    #{description}

    Generate the handler code. Return ONLY the code in a ```elixir block.
    """
  end

  @spec helpers_generation_prompt([map()], String.t(), String.t()) :: String.t()
  def helpers_generation_prompt(helper_files, handler_code, description) do
    file_list =
      helper_files
      |> Enum.map(fn f -> "- #{f["path"]}: #{f["description"]}" end)
      |> Enum.join("\n")

    """
    You are generating HELPER FILES for an Elixir API handler project.

    ## API Description
    #{description}

    ## Handler Code (already generated, reference only)
    ```elixir
    #{handler_code}
    ```

    ## Files to Generate
    #{file_list}

    Generate ALL helper files in a single response. Separate each file with a delimiter line:

    ===== /src/filename.ex =====
    ```elixir
    (file content here)
    ```

    ## CRITICAL: Every file MUST start with `defmodule`
    Every helper file MUST wrap ALL code inside a `defmodule`. Code with `@doc`, `@spec`,
    or `@moduledoc` outside of a `defmodule` WILL NOT COMPILE and will be rejected.

    WRONG (will fail):
    ```elixir
    @moduledoc "Helpers"
    def my_function, do: :ok
    ```

    RIGHT (will compile):
    ```elixir
    defmodule Helpers do
      @moduledoc "Helpers"
      def my_function, do: :ok
    end
    ```

    ## Rules
    - Generate code for EACH file listed above
    - `/src/request_schema.ex` MUST define `defmodule Request` with `use Blackboex.Schema`,
      `embedded_schema`, and `def changeset(params)` with validations
    - `/src/response_schema.ex` MUST define `defmodule Response` with `use Blackboex.Schema`
      and `embedded_schema` documenting the output fields
    - `/src/helpers.ex` MUST define `defmodule Helpers do ... end` wrapping ALL code
    - EVERY file MUST have exactly ONE top-level `defmodule` wrapping all code
    - Use `use Blackboex.Schema` for schema modules (Request, Response, nested embeds)
    - Helper modules can define public functions referenced by the handler
    - Keep each file focused and under 80 lines
    - Every `defmodule` must have `@moduledoc`
    - Every public `def` must have `@doc` and `@spec`
    - Follow the same allowed/prohibited module rules as the handler

    ## Allowed Modules
    #{Enum.join(SecurityConfig.allowed_modules(), ", ")}

    ## Prohibited Modules
    #{Enum.join(SecurityConfig.prohibited_modules(), ", ")}
    """
  end

  @spec multi_file_edit_prompt([map()], String.t()) :: String.t()
  def multi_file_edit_prompt(current_files, instruction) do
    files_section =
      current_files
      |> Enum.map(fn file ->
        """
        ### #{file.path}
        ```elixir
        #{file.content}
        ```
        """
      end)
      |> Enum.join("\n")

    """
    ## Current Project Files
    #{files_section}

    ## Edit Instruction
    #{instruction}

    Return SEARCH/REPLACE blocks for the files that need to change.
    Prefix each group of changes with the file path:

    <<<< /src/handler.ex
    <<<<<<< SEARCH
    (exact lines to find)
    =======
    (replacement lines)
    >>>>>>> REPLACE

    <<<< /src/helpers.ex
    <<<<<<< SEARCH
    (exact lines to find)
    =======
    (replacement lines)
    >>>>>>> REPLACE

    Rules:
    - Only modify files that need to change
    - The `<<<<` prefix line indicates which file the following SEARCH/REPLACE block applies to
    - SEARCH blocks must match exactly (whitespace matters)
    - You can have multiple SEARCH/REPLACE blocks per file
    - Before the blocks, write a brief explanation of what you changed
    """
  end
end
