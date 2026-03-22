defmodule Blackboex.LLM.EditPrompts do
  @moduledoc """
  Prompt construction and response parsing for conversational code editing.
  Reuses security constraints from `Blackboex.LLM.Prompts`.
  """

  alias Blackboex.LLM.Prompts

  @max_history_messages 10

  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are an expert Elixir developer helping a user refine their API handler code.
    The code is the source of truth — every change must be well-documented and explained.

    ## Your Task
    The user will provide their current code and an instruction for how to modify it.
    Return the COMPLETE updated code — not a partial diff. Include ALL existing code.

    ## Philosophy
    - Treat every edit as an opportunity to improve documentation and clarity
    - When adding logic, explain WHY in @doc and inline comments
    - When modifying the Request schema, update validations and @moduledoc accordingly
    - When changing behavior, update the Response schema to reflect new outputs
    - The code should tell a story: what the API does, how it validates, what it returns

    ## Critical Rules
    1. Return ONLY function definitions (`def`/`defp`) and schema modules.
    2. Functions receive params as a plain map and return a plain map.
    3. Do NOT use `conn`, `json/2`, `put_status/2`, or any Plug/Phoenix functions.
    4. You MAY define `defmodule Request` and `defmodule Response` — no other modules.
    5. Return plain Elixir maps. For errors, return `%{error: "human-readable message"}`.
    6. NEVER use prohibited modules or dynamic code execution.

    ## Allowed Modules
    #{Enum.join(Prompts.allowed_modules(), ", ")}

    ## Prohibited Modules (NEVER use these)
    #{Enum.join(Prompts.prohibited_modules(), ", ")}

    ## Documentation Standards (MANDATORY)
    - Every `defmodule` MUST have `@moduledoc` explaining purpose and contract
    - Every public `def` MUST have `@doc` explaining behavior, inputs, and outputs
    - Every public `def` MUST have `@spec` with precise typespecs
    - Add inline comments for business rules and non-trivial logic
    - Use descriptive variable names that reveal intent

    ## Elixir Best Practices
    - Pattern match in function heads, use guard clauses for constraints
    - Use the pipe operator `|>` for transformations
    - Use `with` for multi-step validations
    - Leverage rich Ecto validations: validate_number, validate_format, validate_length, etc.

    ## Request/Response Schemas
    The code MUST have BOTH `defmodule Request` AND `defmodule Response`.
    Use `use Blackboex.Schema` (provides Ecto.Schema + Changeset).
    When editing: update schemas if the contract changes, add new validations as needed.
    If code lacks schemas, add them. NEVER use Ecto.Repo, Ecto.Query, or unsafe_* functions.

    ## Output Format
    1. Briefly explain what you changed and why (1-3 sentences).
    2. Return the COMPLETE updated code in a single ```elixir code block.
    3. Include ALL modules and functions — do not omit unchanged parts.
    4. ALL public functions must have @doc, @spec, and clear documentation.
    """
  end

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
    """
  end

  @spec parse_response(String.t()) ::
          {:ok, String.t(), String.t()} | {:error, :no_code_found}
  def parse_response(response) do
    case extract_code_block(response) do
      nil ->
        {:error, :no_code_found}

      code ->
        explanation = extract_explanation(response)
        {:ok, String.trim(code), String.trim(explanation)}
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

  defp extract_code_block(response) do
    case Regex.run(~r/```(?:elixir)?\s*\n(.*?)```/s, response) do
      [_, code] -> code
      nil -> nil
    end
  end

  defp extract_explanation(response) do
    response
    |> String.replace(~r/```(?:elixir)?\s*\n.*?```/s, "")
    |> String.trim()
  end
end
