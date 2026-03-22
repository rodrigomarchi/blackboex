defmodule Blackboex.CodeGen.SchemaExtractor do
  @moduledoc """
  Extracts request/response schema information from compiled API modules
  by inspecting nested Request/Response modules that use Ecto.Schema.
  """

  @ecto_to_json_schema %{
    :string => "string",
    :integer => "integer",
    :float => "number",
    :boolean => "boolean",
    :map => "object",
    :decimal => "number",
    :binary => "string",
    :utc_datetime => "string",
    :naive_datetime => "string",
    :date => "string",
    :time => "string"
  }

  @spec extract(module()) :: {:ok, map()} | {:error, :no_schema}
  def extract(compiled_module) do
    request_mod = Module.concat(compiled_module, :Request)
    response_mod = Module.concat(compiled_module, :Response)

    request_schema = extract_embedded_schema(request_mod)
    response_schema = extract_embedded_schema(response_mod)

    if request_schema || response_schema do
      {:ok, %{request: request_schema, response: response_schema}}
    else
      {:error, :no_schema}
    end
  end

  @spec to_param_schema(map()) :: map()
  def to_param_schema(%{request: request}) when is_map(request) do
    Map.new(request.fields, fn {field, type} ->
      {to_string(field), ecto_type_to_string(type)}
    end)
  end

  def to_param_schema(_), do: %{}

  @spec to_json_schema(map()) :: map()
  def to_json_schema(schema) when is_map(schema) do
    properties =
      Map.new(schema.fields, fn {field, type} ->
        {to_string(field), %{"type" => ecto_type_to_json(type)}}
      end)

    required = Enum.map(schema.required || [], &to_string/1)

    result = %{
      "type" => "object",
      "properties" => properties
    }

    if required != [], do: Map.put(result, "required", required), else: result
  end

  @doc "Generate an example request/response map from extracted schema fields."
  @spec generate_example(map() | nil) :: map()
  def generate_example(nil), do: %{}

  def generate_example(%{fields: fields}) do
    Map.new(fields, fn {field, type} ->
      {to_string(field), sample_value(type)}
    end)
  end

  defp sample_value(:string), do: "example"
  defp sample_value(:integer), do: 42
  defp sample_value(:float), do: 3.14
  defp sample_value(:decimal), do: 3.14
  defp sample_value(:boolean), do: true
  defp sample_value(:map), do: %{}
  defp sample_value(:date), do: Date.utc_today() |> Date.to_iso8601()
  defp sample_value(:time), do: Time.utc_now() |> Time.truncate(:second) |> Time.to_iso8601()

  defp sample_value(:utc_datetime),
    do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp sample_value(:naive_datetime),
    do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

  defp sample_value(:binary), do: ""
  defp sample_value(_), do: "value"

  @spec extract_embedded_schema(module()) :: map() | nil
  defp extract_embedded_schema(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) do
      fields = module.__schema__(:fields)
      types = Map.new(fields, fn f -> {f, module.__schema__(:type, f)} end)

      required = detect_required_fields(module)

      %{fields: types, required: required}
    else
      nil
    end
  end

  @spec detect_required_fields(module()) :: [atom()]
  defp detect_required_fields(module) do
    if function_exported?(module, :changeset, 1) do
      try do
        changeset = module.changeset(%{})

        changeset.errors
        |> Enum.filter(fn {_field, {_msg, opts}} -> opts[:validation] == :required end)
        |> Enum.map(fn {field, _} -> field end)
      rescue
        _ -> []
      end
    else
      []
    end
  end

  @spec ecto_type_to_json(atom()) :: String.t()
  defp ecto_type_to_json(type) do
    Map.get(@ecto_to_json_schema, type, "string")
  end

  @spec ecto_type_to_string(atom()) :: String.t()
  defp ecto_type_to_string(type) do
    case type do
      :integer -> "integer"
      :float -> "float"
      :boolean -> "boolean"
      :map -> "map"
      _ -> "string"
    end
  end
end
