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

    ## Your Task
    The user will provide their current code and an instruction for how to modify it.
    You must return the COMPLETE updated code — not a partial diff or patch.
    Replace the entire handler code with the improved version.

    ## Critical Rules (same as code generation)

    1. Return ONLY function definitions (`def` and `defp`) — NOT a full module.
    2. Functions receive params as a plain map and return a plain map.
    3. Do NOT use `conn`, `json/2`, `put_status/2`, `send_resp/3`, or any Plug/Phoenix functions.
    4. Do NOT define modules (`defmodule`), `use`, `import`, or `require` statements.
    5. Return plain Elixir maps like `%{result: value}`. The framework handles JSON encoding.
    6. For errors, return `%{error: "message"}` — the framework handles HTTP status codes.
    7. Use pattern matching extensively.
    8. NEVER use modules from the prohibited list.
    9. NEVER access the filesystem, execute system commands, or open network connections.
    10. NEVER use `Code.eval_string`, `Code.compile_string`, or any dynamic code execution.
    11. NEVER use `spawn`, `send`, `receive`, `exit`, `throw`, `apply/3`, or `String.to_atom`.

    ## Allowed Modules
    #{Enum.join(Prompts.allowed_modules(), ", ")}

    ## Prohibited Modules (NEVER use these)
    #{Enum.join(Prompts.prohibited_modules(), ", ")}

    ## Code Quality Requirements
    - Every public function MUST have @doc with a clear description of what it does
    - Every public function MUST have @spec with proper typespecs
    - Private functions (defp) SHOULD have @spec but @doc is optional
    - Use descriptive variable names (not single letters like x, y)
    - Add inline comments only where logic is non-obvious
    - Follow Elixir standard formatting conventions (mix format compatible)
    - Avoid long lines (max 120 chars)
    - Use pattern matching in function heads instead of conditionals when appropriate
    - Group related functions together

    ## Output Format
    1. First, briefly explain what you changed and why (1-3 sentences).
    2. Then return the COMPLETE updated code in a single ```elixir code block.
    3. The code block must contain ALL function definitions — do not omit unchanged functions.
    4. The returned code MUST include @doc and @spec on ALL public functions.
    5. The code MUST be compatible with `mix format` and `mix credo --strict`.
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
