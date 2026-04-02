defmodule Blackboex.LLM.Prompts do
  @moduledoc """
  System prompts and prompt builders for LLM code generation.
  Contains security constraints, allowed/prohibited modules, and template integration.
  """

  alias Blackboex.LLM.Templates

  @allowed_modules ~w(
    Enum Map List String Integer Float Tuple Keyword
    MapSet Date Time DateTime NaiveDateTime Calendar
    Regex URI Base Jason
    Access Stream Range
    Blackboex.Schema Ecto.Schema Ecto.Changeset Ecto.Type Ecto.UUID Ecto.Enum
  )

  @prohibited_modules ~w(
    File System IO Code Port Process Node
    Application :erlang :os Module Kernel.SpecialForms
    GenServer Agent Task Supervisor
    ETS :ets DETS :dets
  )

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
    4. You MAY define `defmodule Request` and `defmodule Response` — no other modules.
    5. Return plain Elixir maps like `%{result: value}`. The framework handles JSON.
    6. For errors, return `%{error: "human-readable message"}`.
    7. NEVER use modules from the prohibited list.
    8. NEVER access filesystem, network, or system commands.
    9. NEVER use dynamic code execution, spawn, send, receive, or atom creation.

    ## Allowed Modules
    #{Enum.join(@allowed_modules, ", ")}

    ## Prohibited Modules (NEVER use these)
    #{Enum.join(@prohibited_modules, ", ")}

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

    ## Code Quality Rules (ENFORCED BY AUTOMATED LINTER — violations are rejected)
    1. **Max 120 characters per line** — break long lines with multi-line syntax
    2. **Max 20 lines per function** — extract `defp` helpers for complex logic
    3. **Max 3 levels of nesting** (if/case/cond/with) — flatten with `with`, guards, or early return
    4. **Every public `def` MUST have `@doc` directly above it** (before `@spec`)
    5. **Every public `def` MUST have `@spec` directly above it** (after `@doc`)
    6. **Code MUST be compatible with `mix format`** — standard Elixir formatting

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

    # WRONG: nesting depth > 3
    if a do
      if b do
        case c do    # depth 3 — this is the limit
          :x ->
            if d do   # depth 4 — REJECTED
            end
        end
      end
    end

    # WRONG: function > 20 lines — extract helpers instead
    def handle(params) do
      # ... 25 lines of logic ...
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
      if changeset.valid?, do: {:ok, Ecto.Changeset.apply_changes(changeset)}, else: {:error, "Invalid input"}
    end
    ```

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

    Rules for schemas:
    - ALWAYS define BOTH `defmodule Request` AND `defmodule Response`
    - Request MUST have `changeset/1` with all relevant validations
    - Response documents the success output (no changeset needed)
    - Use rich Ecto validations: `validate_required`, `validate_number`, `validate_length`,
      `validate_format`, `validate_inclusion`, etc.
    - The handler MUST use `Request.changeset(params)` to validate input
    - ONLY module names allowed: Request, Response, Params
    - NEVER use `Ecto.Repo`, `Ecto.Query`, or `unsafe_*` functions

    ## Output Format
    Return ONLY Elixir code in a single ```elixir code block.
    The code must contain: Request module, Response module, handler functions (def/defp).
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

  @spec allowed_modules() :: [String.t()]
  def allowed_modules, do: @allowed_modules

  @spec prohibited_modules() :: [String.t()]
  def prohibited_modules, do: @prohibited_modules
end
