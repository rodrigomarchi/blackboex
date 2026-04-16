defmodule Blackboex.Playgrounds.Completer do
  @moduledoc """
  Provides code completion for the Playground editor.

  Uses module introspection (`__info__/1`) to list functions of allowed modules.
  Results are filtered against `Executor.allowed_modules/0` to prevent leaking
  information about blocked modules.
  """

  alias Blackboex.Playgrounds.Executor

  @module_map %{
    "Enum" => Enum,
    "Map" => Map,
    "List" => List,
    "String" => String,
    "Integer" => Integer,
    "Float" => Float,
    "Tuple" => Tuple,
    "Keyword" => Keyword,
    "MapSet" => MapSet,
    "Date" => Date,
    "Time" => Time,
    "DateTime" => DateTime,
    "NaiveDateTime" => NaiveDateTime,
    "Calendar" => Calendar,
    "Regex" => Regex,
    "URI" => URI,
    "Base" => Base,
    "Jason" => Jason,
    "Access" => Access,
    "Stream" => Stream,
    "Range" => Range,
    "Atom" => Atom,
    "IO" => IO,
    "Inspect" => Inspect,
    "Kernel" => Kernel,
    "Bitwise" => Bitwise
  }

  @spec complete(String.t()) :: [map()]
  def complete(""), do: []
  def complete("."), do: []

  def complete(hint) when is_binary(hint) do
    allowed = Executor.allowed_modules()

    case String.split(hint, ".", parts: 2) do
      [module_name, func_prefix] ->
        complete_functions(module_name, func_prefix, allowed)

      [prefix] ->
        complete_modules(prefix, allowed)
    end
  end

  defp complete_modules(prefix, allowed) do
    allowed
    |> Enum.filter(&String.starts_with?(&1, prefix))
    |> Enum.sort()
    |> Enum.map(fn name ->
      %{label: name, type: "module", detail: "module"}
    end)
  end

  defp complete_functions(module_name, func_prefix, allowed) do
    with true <- module_name in allowed,
         module when not is_nil(module) <- Map.get(@module_map, module_name) do
      list_module_functions(module, func_prefix, module_name)
    else
      _ -> []
    end
  end

  defp list_module_functions(module, func_prefix, module_name) do
    functions = module.__info__(:functions)
    macros = module.__info__(:macros)

    (functions ++ macros)
    |> Enum.filter(fn {name, _arity} ->
      func_prefix == "" or String.starts_with?(to_string(name), func_prefix)
    end)
    |> Enum.uniq()
    |> Enum.sort_by(fn {name, arity} -> {to_string(name), arity} end)
    |> Enum.map(fn {name, arity} ->
      %{label: "#{name}/#{arity}", type: "function", detail: module_name}
    end)
  end
end
