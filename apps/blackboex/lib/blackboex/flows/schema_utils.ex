defmodule Blackboex.Flows.SchemaUtils do
  @moduledoc """
  Pure schema manipulation utilities for flow node schemas.

  Contains path building, field inspection, value formatting, and constraint
  helpers used by the schema builder UI and by domain-layer schema operations.
  """

  @doc """
  Builds a dot-separated path string for a field at the given index.

  ## Examples

      iex> Blackboex.Flows.SchemaUtils.build_path("", 0)
      "0"

      iex> Blackboex.Flows.SchemaUtils.build_path("fields", 2)
      "fields.2"

  """
  @spec build_path(String.t(), non_neg_integer()) :: String.t()
  def build_path("", index), do: "#{index}"
  def build_path(parent, index), do: "#{parent}.#{index}"

  @doc """
  Formats an enum constraint list as a comma-separated string for display.

  ## Examples

      iex> Blackboex.Flows.SchemaUtils.format_enum(nil)
      ""

      iex> Blackboex.Flows.SchemaUtils.format_enum(["a", "b"])
      "a,b"

  """
  @spec format_enum(list() | nil | term()) :: String.t()
  def format_enum(nil), do: ""
  def format_enum(list) when is_list(list), do: Enum.join(list, ",")
  def format_enum(_), do: ""

  @doc """
  Formats an initial value for display in a text/number input.
  """
  @spec format_initial_value(term()) :: String.t()
  def format_initial_value(nil), do: ""
  def format_initial_value(val), do: to_string(val)

  @doc """
  Formats a value as pretty-printed JSON, or falls back to `to_string/1`.
  """
  @spec format_json_value(term()) :: String.t()
  def format_json_value(nil), do: ""

  def format_json_value(val) when is_map(val) or is_list(val) do
    Jason.encode!(val, pretty: true)
  end

  def format_json_value(val), do: to_string(val)

  @doc """
  Returns the state variable mapped to a response field, or `""` if none.
  """
  @spec find_mapped_variable(list(map()), String.t()) :: String.t()
  def find_mapped_variable(mapping, response_field) do
    case Enum.find(mapping, &(&1["response_field"] == response_field)) do
      nil -> ""
      entry -> entry["state_variable"]
    end
  end

  @doc """
  Returns `true` if the field has any non-empty constraint (ignoring `item_type`).
  """
  @spec has_any_constraint?(map()) :: boolean()
  def has_any_constraint?(field) do
    constraints = field["constraints"] || %{}

    Enum.any?(constraints, fn {key, val} ->
      key != "item_type" and val != nil and val != "" and val != []
    end)
  end
end
