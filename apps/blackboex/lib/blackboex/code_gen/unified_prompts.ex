defmodule Blackboex.CodeGen.UnifiedPrompts do
  @moduledoc """
  Prompt construction for the unified pipeline's fix cycle.
  When code fails compilation, linting, or tests, these prompts
  ask the LLM to fix the issues while maintaining code quality.
  """

  alias Blackboex.LLM.Prompts

  @spec build_fix_code_prompt(String.t(), [String.t()]) :: String.t()
  def build_fix_code_prompt(code, errors) do
    errors_text = Enum.join(errors, "\n- ")

    """
    The following Elixir handler code has issues that need to be fixed.

    ## Current Code
    ```elixir
    #{sanitize(code)}
    ```

    ## Issues Found
    - #{errors_text}

    ## Instructions
    Fix ALL of the issues listed above. Return the COMPLETE corrected code.

    ## Critical Rules
    1. Return ONLY function definitions (`def` and `defp`) — NOT a full module.
    2. Every public `def` MUST have @doc directly above it, then @spec, then def.
    3. The code MUST compile without warnings.
    4. The code MUST be compatible with `mix format` and `mix credo --strict`.
    5. Do NOT use prohibited modules: #{Enum.join(Prompts.prohibited_modules(), ", ")}
    6. Functions receive params as a plain map and return a plain map.
    7. Do NOT use `conn`, `json/2`, `put_status/2`, `send_resp/3`, or any Plug/Phoenix functions.
    8. Max 120 characters per line — break long lines.
    9. Max 20 lines per function — extract `defp` helpers for complex logic.
    10. Max 3 levels of nesting (if/case/cond/with) — use `with` or function clauses to flatten.
    11. Only allowed defmodule names: Request, Response, Params.

    Return the fixed code in a single ```elixir code block.
    """
  end

  @spec build_fix_test_prompt(String.t(), [String.t()], String.t()) :: String.t()
  def build_fix_test_prompt(test_code, errors, handler_code) do
    errors_text = Enum.join(errors, "\n- ")

    """
    The following ExUnit test code has issues that need to be fixed.

    ## Handler Code Being Tested
    ```elixir
    #{sanitize(handler_code)}
    ```

    ## Current Test Code
    ```elixir
    #{sanitize(test_code)}
    ```

    ## Issues Found
    - #{errors_text}

    ## Instructions
    Fix ALL of the issues listed above. Return the COMPLETE corrected test code.
    The tests must validate the handler code shown above.

    ## Rules
    1. Return a complete ExUnit test module with `use ExUnit.Case`.
    2. Call handler functions via `Handler.handle(...)` — do NOT redefine them.
    3. The `Handler` module is compiled separately and available at runtime.
    4. DO NOT copy handler function definitions into the test module.
    5. Include a @moduledoc describing what is being tested.
    6. Use descriptive test names.
    7. Do NOT use Req, HTTPoison, File, System, Code, Process, or I/O modules.
    8. The code MUST be compatible with `mix format`.

    Return the fixed test code in a single ```elixir code block.
    """
  end

  @spec parse_response(String.t()) :: {:ok, String.t()} | {:error, :no_code_found}
  def parse_response(response) do
    case Regex.run(~r/```(?:elixir)?\s*\n(.*?)```/s, response) do
      [_, code] -> {:ok, String.trim(code)}
      nil -> {:error, :no_code_found}
    end
  end

  defp sanitize(text) do
    String.replace(text, "```", "` ` `")
  end
end
