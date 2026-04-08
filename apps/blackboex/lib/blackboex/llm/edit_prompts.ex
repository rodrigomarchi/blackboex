defmodule Blackboex.LLM.EditPrompts do
  @moduledoc """
  Prompt construction for conversational code editing.
  Uses SEARCH/REPLACE block format for efficient diff-based edits.
  """

  alias Blackboex.LLM.PromptFragments

  @max_history_messages 10

  # ── System Prompts ──────────────────────────────────────────────────────

  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are an expert Elixir developer helping a user refine their API handler code.

    ## Your Task
    The user will provide their current code and an instruction for how to modify it.
    Return ONLY the changes using SEARCH/REPLACE blocks. Do NOT return the full file.

    #{PromptFragments.search_replace_format()}

    Before the blocks, write a 1-3 sentence explanation of what you changed and why.

    #{PromptFragments.handler_rules()}
    #{PromptFragments.allowed_and_prohibited_modules()}

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

  # ── Private ─────────────────────────────────────────────────────────────

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
