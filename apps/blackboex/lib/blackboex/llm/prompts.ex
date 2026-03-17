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
    You are an expert Elixir developer. You generate pure handler functions for REST API endpoints.

    ## Critical Rules

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
    #{Enum.join(@allowed_modules, ", ")}

    ## Prohibited Modules (NEVER use these)
    #{Enum.join(@prohibited_modules, ", ")}

    ## Output Format
    Return ONLY Elixir code wrapped in a single ```elixir code block.
    The code must contain function definitions only (def/defp).
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
