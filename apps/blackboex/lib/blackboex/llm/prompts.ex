defmodule Blackboex.LLM.Prompts do
  @moduledoc """
  System prompts and prompt builders for LLM code generation.
  Composes from `PromptFragments` for shared rules and `SecurityConfig` for module lists.
  """

  alias Blackboex.LLM.PromptFragments

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

    #{PromptFragments.handler_rules()}
    #{PromptFragments.allowed_and_prohibited_modules()}
    #{PromptFragments.documentation_standards()}
    #{PromptFragments.elixir_best_practices()}
    #{PromptFragments.elixir_syntax_rules()}
    #{PromptFragments.code_quality_rules()}
    #{PromptFragments.function_decomposition()}
    #{PromptFragments.schema_rules()}

    ## Output Format
    Return ONLY Elixir code in a ```elixir code block.
    The code must contain: Request module, Response module, handler functions (def/defp).
    When generating a single file, return one code block.
    When generating as part of a multi-file project, follow the specific instructions for that file.
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

  # ── Generation.ex extraction ──────────────────────────────────

  @doc "System prompt for code generation (combines system_prompt + template + instruction)."
  @spec generation_system_prompt(atom()) :: String.t()
  def generation_system_prompt(template_type) do
    alias Blackboex.LLM.Templates

    """
    #{system_prompt()}

    #{Templates.get(template_type)}

    Generate the handler code for this API.
    Return the code in a single ```elixir code block. No explanations outside the block.
    """
  end

  @doc "System prompt for multi-file handler generation."
  @spec handler_system_prompt(atom(), String.t(), [map()]) :: String.t()
  def handler_system_prompt(template_type, description, manifest) do
    alias Blackboex.LLM.Templates

    """
    #{system_prompt()}

    #{Templates.get(template_type)}

    #{handler_generation_prompt(description, manifest)}
    """
  end

  @doc "System prompt for generating a single helper file in a multi-file project."
  @spec helper_file_system_prompt(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def helper_file_system_prompt(description, context, path, file_desc) do
    """
    #{system_prompt()}

    You are generating a single helper file for an Elixir API project.

    ## API Description
    #{description}

    ## Already Generated Files (reference only)
    #{context}

    ## File to Generate: #{path}
    Description: #{file_desc}

    Generate ONLY the code for this file. Return it in a single ```elixir block.
    Follow the same rules as the handler: @moduledoc, @doc, @spec on public functions.
    """
  end
end
