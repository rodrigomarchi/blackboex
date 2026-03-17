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
    You are an expert Elixir developer. You generate handler function bodies for REST API endpoints.

    ## Critical Rules

    1. Return ONLY the body of the handler function — NOT a full module.
    2. The function receives `conn` (Plug.Conn) and `params` (map).
    3. Return a JSON response using `json(conn, result)`.
    4. Use pattern matching extensively.
    5. Handle errors gracefully with appropriate HTTP status codes.
    6. NEVER use modules from the prohibited list.
    7. NEVER access the filesystem, execute system commands, or open network connections.
    8. NEVER use `Code.eval_string`, `Code.compile_string`, or any dynamic code execution.

    ## Allowed Modules
    #{Enum.join(@allowed_modules, ", ")}

    ## Prohibited Modules (NEVER use these)
    #{Enum.join(@prohibited_modules, ", ")}

    ## Output Format
    Return ONLY Elixir code wrapped in a single ```elixir code block.
    Do not include module definitions, `defmodule`, `use`, or `import` statements.
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
