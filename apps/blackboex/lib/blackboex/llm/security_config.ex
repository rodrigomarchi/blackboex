defmodule Blackboex.LLM.SecurityConfig do
  @moduledoc """
  Security configuration for user-generated code.

  Defines the allowed and prohibited Elixir modules for sandboxed execution.
  Used by the compiler, AST validator, and prompt generators.
  """

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

  @spec allowed_modules() :: [String.t()]
  def allowed_modules, do: @allowed_modules

  @spec prohibited_modules() :: [String.t()]
  def prohibited_modules, do: @prohibited_modules
end
