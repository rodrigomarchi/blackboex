defmodule Blackboex.LLM.EditPrompts do
  @moduledoc """
  Prompt construction and response parsing for conversational code editing.
  Uses SEARCH/REPLACE block format for efficient diff-based edits.
  """

  alias Blackboex.LLM.SecurityConfig

  @max_history_messages 10

  # ── System Prompts ──────────────────────────────────────────────────────

  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are an expert Elixir developer helping a user refine their API handler code.

    ## Your Task
    The user will provide their current code and an instruction for how to modify it.
    Return ONLY the changes using SEARCH/REPLACE blocks. Do NOT return the full file.

    For each change, use this exact format:

    <<<<<<< SEARCH
    (exact lines from the current code that need to change)
    =======
    (the new replacement lines)
    >>>>>>> REPLACE

    ## SEARCH/REPLACE Rules
    - The SEARCH block must match the current code EXACTLY (whitespace matters)
    - Include 2-3 lines of surrounding context for accurate matching
    - You can have multiple SEARCH/REPLACE blocks for multiple changes
    - Before the blocks, write a 1-3 sentence explanation of what you changed and why
    - Do NOT return the full file — ONLY the changed sections
    - If you need to ADD new code (not replace existing), use an empty-ish SEARCH with
      just the surrounding context lines where the new code should be inserted

    #{common_rules()}
    """
  end

  @spec fallback_system_prompt() :: String.t()
  def fallback_system_prompt do
    """
    You are an expert Elixir developer helping a user refine their API handler code.

    ## Your Task
    Return the COMPLETE updated code in a single ```elixir code block.
    Include ALL existing code with your changes applied.
    Before the code block, write a 1-3 sentence explanation of what you changed.

    #{common_rules()}
    """
  end

  defp common_rules do
    """
    ## Critical Rules
    1. Return ONLY function definitions (`def`/`defp`) and schema modules.
    2. Functions receive params as a plain map and return a plain map.
    3. Do NOT use `conn`, `json/2`, `put_status/2`, or any Plug/Phoenix functions.
    4. You MAY define `defmodule Request`, `defmodule Response`, and nested schema modules for embeds.
    5. Return plain Elixir maps. For errors, return `%{error: "human-readable message"}`.
    6. NEVER use prohibited modules or dynamic code execution.

    ## Allowed Modules
    #{Enum.join(SecurityConfig.allowed_modules(), ", ")}

    ## Prohibited Modules (NEVER use these)
    #{Enum.join(SecurityConfig.prohibited_modules(), ", ")}

    ## Code Quality
    - Every `defmodule` MUST have `@moduledoc`
    - Every public `def` MUST have `@doc` and `@spec`
    - Pattern match in function heads, use guard clauses
    - Use the pipe operator `|>` for transformations
    - The code MUST have BOTH `defmodule Request` AND `defmodule Response`
    - Use `use Blackboex.Schema` for schemas
    """
  end

  # ── Prompt Builders ─────────────────────────────────────────────────────

  @spec build_edit_prompt(String.t(), String.t(), [map()]) :: String.t()
  def build_edit_prompt(current_code, instruction, history) do
    history_section = format_history(history)

    """
    #{history_section}## Current Code
    ```elixir
    #{current_code}
    ```

    ## Instruction
    #{instruction}

    Return ONLY SEARCH/REPLACE blocks for the changes needed.
    """
  end

  @spec build_search_retry_prompt(String.t(), String.t(), String.t()) :: String.t()
  def build_search_retry_prompt(current_code, instruction, failed_search) do
    """
    Your previous SEARCH block did not match the current code. Here is the code:

    ```elixir
    #{current_code}
    ```

    The SEARCH block that failed to match:
    ```
    #{failed_search}
    ```

    Please provide corrected SEARCH/REPLACE blocks for: #{instruction}
    Make sure the SEARCH block matches the code EXACTLY (including whitespace and indentation).
    """
  end

  # ── Response Parsing ────────────────────────────────────────────────────

  @spec parse_response(String.t()) ::
          {:ok, :search_replace, [%{search: String.t(), replace: String.t()}], String.t()}
          | {:ok, :full_code, String.t(), String.t()}
          | {:error, :no_changes_found}
  def parse_response(response) do
    blocks = extract_search_replace_blocks(response)

    if blocks != [] do
      explanation = extract_explanation_before_blocks(response)
      {:ok, :search_replace, blocks, String.trim(explanation)}
    else
      # Fallback: LLM may have returned full code in ```elixir block
      case extract_code_block(response) do
        nil ->
          {:error, :no_changes_found}

        code ->
          explanation = extract_explanation(response)
          {:ok, :full_code, String.trim(code), String.trim(explanation)}
      end
    end
  end

  # ── Public Helpers (used by pipeline fallback) ──────────────────────────

  @spec extract_code_block(String.t()) :: String.t() | nil
  def extract_code_block(response) do
    case Regex.run(~r/```(?:elixir)?\s*\n(.*?)```/s, response) do
      [_, code] -> code
      nil -> nil
    end
  end

  @spec extract_explanation(String.t()) :: String.t()
  def extract_explanation(response) do
    response
    |> String.replace(~r/```(?:elixir)?\s*\n.*?```/s, "")
    |> String.replace(~r/<<<<<<< SEARCH.*?>>>>>>> REPLACE/s, "")
    |> String.trim()
  end

  # ── Private ─────────────────────────────────────────────────────────────

  defp extract_search_replace_blocks(response) do
    ~r/<<<<<<< SEARCH\n(.*?)\n=======\n(.*?)\n>>>>>>> REPLACE/s
    |> Regex.scan(response)
    |> Enum.map(fn [_full, search, replace] ->
      %{search: search, replace: replace}
    end)
  end

  defp extract_explanation_before_blocks(response) do
    case String.split(response, "<<<<<<< SEARCH", parts: 2) do
      [before, _] -> String.trim(before)
      [only] -> String.trim(only)
    end
  end

  defp format_history([]), do: ""

  defp format_history(history) do
    recent = Enum.take(history, -@max_history_messages)

    formatted =
      recent
      |> Enum.map(fn msg ->
        role = String.capitalize(msg["role"])
        "#{role}: #{msg["content"]}"
      end)
      |> Enum.join("\n\n")

    """
    ## Conversation History
    #{formatted}

    """
  end
end
