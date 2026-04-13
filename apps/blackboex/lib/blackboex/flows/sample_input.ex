defmodule Blackboex.Flows.SampleInput do
  @moduledoc """
  Generates example input JSON from a flow's start node payload_schema.

  Used to pre-fill the Test Run modal with a valid example payload
  that respects field types and constraints (enum, min/max, min_length, etc.).
  """

  alias Blackboex.Flows.Flow

  @default_string "example"
  @default_integer 42
  @default_float 3.14

  @spec generate(Flow.t()) :: map()
  def generate(%Flow{definition: definition}) when is_map(definition) do
    definition
    |> find_start_node()
    |> extract_payload_schema()
    |> generate_example()
  end

  def generate(_), do: %{}

  # ── Private ──────────────────────────────────────────────────────────────

  defp find_start_node(%{"nodes" => nodes}) when is_list(nodes) do
    Enum.find(nodes, &(&1["type"] == "start"))
  end

  defp find_start_node(_), do: nil

  defp extract_payload_schema(%{"data" => %{"payload_schema" => [_ | _] = schema}}) do
    schema
  end

  defp extract_payload_schema(_), do: []

  defp generate_example([]), do: %{}

  defp generate_example(fields) when is_list(fields) do
    fields
    |> Enum.filter(&is_map/1)
    |> Enum.filter(&Map.has_key?(&1, "name"))
    |> Map.new(fn field -> {field["name"], sample_value(field)} end)
  end

  defp sample_value(%{"type" => type} = field) do
    constraints = field["constraints"] || %{}
    sample_for_type(type, constraints, field)
  end

  defp sample_value(_), do: nil

  # ── String ──

  defp sample_for_type("string", constraints, _field) do
    cond do
      enum = constraints["enum"] ->
        List.first(enum)

      min = constraints["min_length"] ->
        String.duplicate("a", min)

      max = constraints["max_length"] ->
        String.slice(@default_string, 0, max)

      true ->
        @default_string
    end
  end

  # ── Integer ──

  defp sample_for_type("integer", constraints, _field) do
    min = constraints["min"]
    max = constraints["max"]

    cond do
      min -> min
      max && @default_integer > max -> max
      true -> @default_integer
    end
  end

  # ── Float ──

  defp sample_for_type("float", constraints, _field) do
    min = constraints["min"]
    max = constraints["max"]

    cond do
      min -> min
      max && @default_float > max -> max
      true -> @default_float
    end
  end

  # ── Boolean ──

  defp sample_for_type("boolean", _constraints, _field), do: true

  # ── Array ──

  defp sample_for_type("array", constraints, _field) do
    item_type = constraints["item_type"]
    item_fields = constraints["item_fields"] || []
    min_items = constraints["min_items"] || 1
    count = max(min_items, 1)

    cond do
      item_type == "object" && is_list(item_fields) ->
        item = generate_example(item_fields)
        List.duplicate(item, count)

      is_binary(item_type) ->
        item = sample_for_type(item_type, %{}, %{})
        List.duplicate(item, count)

      true ->
        []
    end
  end

  # ── Object ──

  defp sample_for_type("object", _constraints, %{"fields" => fields})
       when is_list(fields) do
    generate_example(fields)
  end

  defp sample_for_type("object", _constraints, _field), do: %{}

  # ── Unknown ──

  defp sample_for_type(_unknown, _constraints, _field), do: nil
end
