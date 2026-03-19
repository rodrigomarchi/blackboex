defmodule Blackboex.Testing.ResponseValidator do
  @moduledoc """
  Validates API responses against a param_schema.
  """

  @type violation :: %{type: atom(), message: String.t(), path: String.t() | nil}

  @spec validate(map(), map() | nil) :: [violation()]
  def validate(_response, nil), do: []
  def validate(_response, schema) when schema == %{}, do: []

  def validate(response, schema) do
    status_violations = validate_status(response.status)
    body_violations = validate_body(response.body, schema)
    status_violations ++ body_violations
  end

  defp validate_status(status) when status >= 200 and status < 300, do: []

  defp validate_status(status) do
    [%{type: :unexpected_status, message: "Expected 2xx status, got #{status}", path: nil}]
  end

  defp validate_body(body, schema) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} when is_map(parsed) ->
        validate_fields(parsed, schema)

      {:ok, _} ->
        []

      {:error, _} ->
        [%{type: :invalid_json, message: "Response body is not valid JSON", path: nil}]
    end
  end

  defp validate_body(_body, _schema), do: []

  defp validate_fields(parsed, schema) do
    missing = find_missing_fields(parsed, schema)
    wrong_types = find_wrong_types(parsed, schema)
    missing ++ wrong_types
  end

  defp find_missing_fields(parsed, schema) do
    schema
    |> Enum.reject(fn {key, _type} -> Map.has_key?(parsed, key) end)
    |> Enum.map(fn {key, _type} ->
      %{type: :missing_field, message: "Missing field '#{key}'", path: key}
    end)
  end

  defp find_wrong_types(parsed, schema) do
    schema
    |> Enum.filter(fn {key, _type} -> Map.has_key?(parsed, key) end)
    |> Enum.reject(fn {key, type} -> type_matches?(Map.get(parsed, key), type) end)
    |> Enum.map(fn {key, type} ->
      actual = Map.get(parsed, key)

      %{
        type: :wrong_type,
        message: "Field '#{key}': expected #{type}, got #{inspect(actual)}",
        path: key
      }
    end)
  end

  defp type_matches?(value, "string"), do: is_binary(value)
  defp type_matches?(value, "integer"), do: is_integer(value)
  defp type_matches?(value, "number"), do: is_number(value)
  defp type_matches?(value, "boolean"), do: is_boolean(value)
  defp type_matches?(value, "array"), do: is_list(value)
  defp type_matches?(value, "object"), do: is_map(value)
  defp type_matches?(_value, _type), do: true
end
