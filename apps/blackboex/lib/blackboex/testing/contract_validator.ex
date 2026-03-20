defmodule Blackboex.Testing.ContractValidator do
  @moduledoc """
  Validates API responses against OpenAPI spec schemas using ExJsonSchema.
  """

  @type violation :: %{type: atom(), message: String.t(), path: String.t() | nil}

  @spec validate(map(), map()) :: [violation()]
  def validate(%{status: status, body: body}, openapi_spec) when is_map(body) do
    case find_responses(openapi_spec) do
      nil -> []
      responses -> validate_status(responses, to_string(status), body)
    end
  end

  # Non-map bodies (nil, binary) can't be schema-validated
  def validate(_response, _openapi_spec), do: []

  @spec extract_response_schema(map(), integer()) :: map() | nil
  def extract_response_schema(openapi_spec, status_code) do
    case find_responses(openapi_spec) do
      nil -> nil
      responses -> extract_schema_from_responses(responses, to_string(status_code))
    end
  end

  # --- Private ---

  defp validate_status(responses, status_str, body) do
    if Map.has_key?(responses, status_str) do
      case extract_schema_from_responses(responses, status_str) do
        nil -> []
        schema -> validate_body(body, schema)
      end
    else
      documented = Map.keys(responses)

      [
        %{
          type: :undocumented_status,
          message:
            "Status #{status_str} not documented in spec. Documented: #{Enum.join(documented, ", ")}",
          path: nil
        }
      ]
    end
  end

  defp find_responses(openapi_spec) do
    first_path = first_path_key(openapi_spec)

    if first_path do
      first_method = first_method_key(openapi_spec, first_path)

      if first_method do
        get_in(openapi_spec, ["paths", first_path, first_method, "responses"])
      end
    end
  end

  defp validate_body(body, schema) do
    resolved = ExJsonSchema.Schema.resolve(schema)

    case ExJsonSchema.Validator.validate(resolved, body) do
      :ok ->
        []

      {:error, errors} ->
        Enum.map(errors, fn {message, path} ->
          %{
            type: :schema_violation,
            message: message,
            path: path
          }
        end)
    end
  end

  defp extract_schema_from_responses(responses, status_str) do
    get_in(responses, [status_str, "content", "application/json", "schema"])
  end

  defp first_path_key(spec) do
    spec
    |> Map.get("paths", %{})
    |> Map.keys()
    |> List.first()
  end

  defp first_method_key(spec, path) do
    case get_in(spec, ["paths", path]) do
      nil -> nil
      path_item -> path_item |> Map.keys() |> List.first()
    end
  end
end
