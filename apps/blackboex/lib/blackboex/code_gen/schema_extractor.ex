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
      {to_string(field), param_type_to_string(type)}
    end)
  end

  def to_param_schema(_), do: %{}

  @spec to_json_schema(map()) :: map()
  def to_json_schema(schema) when is_map(schema) do
    properties =
      Map.new(schema.fields, fn {field, type} ->
        {to_string(field), json_schema_for_type(type)}
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
      {to_string(field), sample_value(field, type)}
    end)
  end

  # Embedded schema recursion
  defp sample_value(_field, {:embed_one, _mod, nested}) when is_map(nested) do
    generate_example(nested)
  end

  defp sample_value(_field, {:embed_many, _mod, nested}) when is_map(nested) do
    [generate_example(nested)]
  end

  defp sample_value(_field, {:embed_one, _mod, _}), do: %{}
  defp sample_value(_field, {:embed_many, _mod, _}), do: [%{}]

  # Smart field name heuristics — try name-based value first, fall back to type
  defp sample_value(field, type) do
    case smart_value_for_name(field) do
      nil -> type_sample_value(type)
      val -> val
    end
  end

  @spec smart_value_for_name(atom()) :: term() | nil
  defp smart_value_for_name(field) do
    name = to_string(field)

    cond do
      name in ~w(age) -> 30
      name in ~w(year birth_year) -> 2023
      name in ~w(years license_years experience_years) -> 5
      name =~ ~r/price|cost|amount|value|salary|income|premium|total|subtotal|fee/ -> 10_000
      name =~ ~r/_brl$/ -> 10_000.00
      name =~ ~r/_usd$/ -> 1_000.00
      name =~ ~r/_pct$|_percent$|_rate$|rate_pct/ -> 5.0
      name in ~w(quantity qty count) -> 3
      name in ~w(name full_name) -> "John Doe"
      name in ~w(first_name) -> "John"
      name in ~w(last_name surname) -> "Doe"
      name in ~w(email) -> "user@example.com"
      name in ~w(phone telephone mobile) -> "+5511999990000"
      name in ~w(zip_prefix cep_prefix) -> "01"
      name =~ ~r/zip|cep|postal/ -> "01310"
      name in ~w(city) -> "São Paulo"
      name in ~w(state uf) -> "SP"
      name in ~w(country) -> "BR"
      name in ~w(address street) -> "Av. Paulista, 1000"
      name in ~w(cpf) -> "123.456.789-00"
      name in ~w(cnpj) -> "12.345.678/0001-90"
      name in ~w(description) -> "Sample description"
      name in ~w(title) -> "Sample Title"
      name in ~w(type kind) -> "standard"
      name in ~w(status) -> "active"
      name in ~w(currency) -> "BRL"
      name in ~w(percentage percent) -> 10.0
      name in ~w(weight) -> 70.5
      name in ~w(height) -> 175
      name in ~w(score rating) -> 8.5
      name in ~w(latitude lat) -> -23.5505
      name in ~w(longitude lng lon) -> -46.6333
      name =~ ~r/^is_|^has_|^can_|^should_|^allow/ -> true
      name =~ ~r/claims|incidents|accidents/ -> 0
      name in ~w(coverage) -> "comprehensive"
      name in ~w(model) -> "Model X"
      name in ~w(brand make manufacturer) -> "Toyota"
      name in ~w(color) -> "black"
      name in ~w(plate license_plate) -> "ABC1D23"
      true -> nil
    end
  end

  defp type_sample_value(:string), do: "example"
  defp type_sample_value(:integer), do: 42
  defp type_sample_value(:float), do: 3.14
  defp type_sample_value(:decimal), do: 3.14
  defp type_sample_value(:boolean), do: true
  defp type_sample_value(:map), do: %{}
  defp type_sample_value(:date), do: Date.utc_today() |> Date.to_iso8601()
  defp type_sample_value(:time), do: Time.utc_now() |> Time.truncate(:second) |> Time.to_iso8601()

  defp type_sample_value(:utc_datetime),
    do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp type_sample_value(:naive_datetime),
    do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

  defp type_sample_value(:binary), do: ""
  defp type_sample_value(_), do: "value"

  @spec extract_embedded_schema(module()) :: map() | nil
  defp extract_embedded_schema(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) do
      fields = module.__schema__(:fields)
      embeds = extract_embeds(module)
      embed_fields = Map.keys(embeds)

      types =
        fields
        |> Enum.reject(&(&1 in embed_fields))
        |> Map.new(fn f -> {f, module.__schema__(:type, f)} end)
        |> Map.merge(embeds)

      required = detect_required_fields(module)

      %{fields: types, required: required}
    else
      nil
    end
  end

  @spec extract_embeds(module()) :: map()
  defp extract_embeds(module) do
    ones =
      if function_exported?(module, :__schema__, 1) do
        module.__schema__(:embeds)
      else
        []
      end

    Map.new(ones, fn embed_field ->
      embed_type = module.__schema__(:embed, embed_field)

      case embed_type do
        %Ecto.Embedded{cardinality: :one, related: related_mod} ->
          nested = extract_embedded_schema(related_mod)
          {embed_field, {:embed_one, related_mod, nested}}

        %Ecto.Embedded{cardinality: :many, related: related_mod} ->
          nested = extract_embedded_schema(related_mod)
          {embed_field, {:embed_many, related_mod, nested}}

        _ ->
          {embed_field, :map}
      end
    end)
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

  @spec json_schema_for_type(term()) :: map()
  defp json_schema_for_type({:embed_one, _mod, nested}) when is_map(nested) do
    to_json_schema(nested)
  end

  defp json_schema_for_type({:embed_many, _mod, nested}) when is_map(nested) do
    %{"type" => "array", "items" => to_json_schema(nested)}
  end

  defp json_schema_for_type({:embed_one, _mod, _}), do: %{"type" => "object"}

  defp json_schema_for_type({:embed_many, _mod, _}),
    do: %{"type" => "array", "items" => %{"type" => "object"}}

  defp json_schema_for_type(type) when is_atom(type) do
    %{"type" => Map.get(@ecto_to_json_schema, type, "string")}
  end

  defp json_schema_for_type(_), do: %{"type" => "string"}

  @spec param_type_to_string(term()) :: String.t()
  defp param_type_to_string({:embed_one, _mod, _}), do: "object"
  defp param_type_to_string({:embed_many, _mod, _}), do: "array"

  defp param_type_to_string(type) when is_atom(type) do
    case type do
      :integer -> "integer"
      :float -> "float"
      :boolean -> "boolean"
      :map -> "map"
      _ -> "string"
    end
  end

  defp param_type_to_string(_), do: "string"
end
