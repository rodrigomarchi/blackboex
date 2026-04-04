defmodule Blackboex.Testing.SampleData do
  @moduledoc """
  Generates sample request data for API testing based on param_schema or example_request.
  """

  @type result :: %{happy_path: map(), edge_cases: [map()], invalid: [map()]}

  @spec generate(map()) :: result()
  def generate(%{param_schema: schema}) when is_map(schema) and map_size(schema) > 0 do
    happy_path = generate_happy_path(schema)
    edge_cases = generate_edge_cases(schema)
    invalid = generate_invalid(schema)

    %{happy_path: happy_path, edge_cases: edge_cases, invalid: invalid}
  end

  def generate(%{example_request: example}) when is_map(example) and map_size(example) > 0 do
    inferred_schema = infer_schema(example)
    edge_cases = generate_edge_cases(inferred_schema)

    %{happy_path: example, edge_cases: edge_cases, invalid: []}
  end

  def generate(_api) do
    %{happy_path: %{}, edge_cases: [], invalid: []}
  end

  defp generate_happy_path(schema) do
    Map.new(schema, fn {key, type} -> {key, sample_value(type)} end)
  end

  defp sample_value("string"), do: "example"
  defp sample_value("integer"), do: 42
  defp sample_value("number"), do: 3.14
  defp sample_value("boolean"), do: true
  defp sample_value("array"), do: []
  defp sample_value("object"), do: %{}
  defp sample_value(%{} = nested_schema), do: generate_happy_path(nested_schema)
  defp sample_value(_), do: "example"

  defp generate_edge_cases(schema) do
    Enum.flat_map(schema, fn {key, type} ->
      type
      |> edge_values_for()
      |> Enum.map(&build_edge_case(schema, key, &1))
    end)
  end

  defp build_edge_case(schema, target_key, edge_value) do
    Map.new(schema, fn {k, t} ->
      if k == target_key, do: {k, edge_value}, else: {k, sample_value(t)}
    end)
  end

  defp edge_values_for("string") do
    [
      "",
      nil,
      String.duplicate("a", 1001),
      "café résumé naïve",
      "🎉🚀💯",
      "'; DROP TABLE users;--",
      "<script>alert('xss')</script>"
    ]
  end

  defp edge_values_for("integer") do
    [0, -1, nil, -999_999, 999_999_999]
  end

  defp edge_values_for("number") do
    [0, 0.0, -1.5, nil, 999_999_999.99]
  end

  defp edge_values_for("boolean") do
    [false, nil]
  end

  defp edge_values_for(_) do
    [nil, ""]
  end

  defp generate_invalid(schema) do
    Enum.map(schema, fn {key, type} ->
      build_edge_case(schema, key, wrong_type_value(type))
    end)
  end

  defp wrong_type_value("string"), do: 12_345
  defp wrong_type_value("integer"), do: "not_a_number"
  defp wrong_type_value("number"), do: "not_a_number"
  defp wrong_type_value("boolean"), do: "not_a_boolean"
  defp wrong_type_value(_), do: 99_999

  defp infer_schema(example) do
    Map.new(example, fn {key, value} -> {key, infer_type(value)} end)
  end

  defp infer_type(v) when is_binary(v), do: "string"
  defp infer_type(v) when is_integer(v), do: "integer"
  defp infer_type(v) when is_float(v), do: "number"
  defp infer_type(v) when is_boolean(v), do: "boolean"
  defp infer_type(v) when is_list(v), do: "array"
  defp infer_type(v) when is_map(v), do: "object"
  defp infer_type(_), do: "string"
end
