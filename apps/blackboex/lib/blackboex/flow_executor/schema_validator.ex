defmodule Blackboex.FlowExecutor.SchemaValidator do
  @moduledoc """
  Validates schema definitions, runtime payloads, builds initial state,
  and maps state variables to response fields.

  Used by Start and End nodes in the flow executor to enforce typed
  contracts on flow inputs, state variables, and outputs.
  """

  @valid_types ~w(string integer float boolean array object)
  @string_constraints ~w(min_length max_length pattern enum)
  @number_constraints ~w(min max)
  @array_constraints ~w(item_type min_items max_items item_fields)
  @max_depth 3
  @field_name_regex ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/

  # ═══════════════════════════════════════════════════════════════════════════
  # validate_schema_definition/1
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Validates a schema definition is well-formed.

  Returns `:ok` or `{:error, [String.t()]}` with all validation errors.
  """
  @spec validate_schema_definition(list() | any()) :: :ok | {:error, [String.t()]}
  def validate_schema_definition(fields) when is_list(fields) do
    errors = validate_fields(fields, 0)

    # Check duplicate names at top level
    errors = errors ++ check_duplicate_names(fields)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  def validate_schema_definition(_), do: {:error, ["schema must be a list"]}

  defp validate_fields(fields, depth) do
    Enum.flat_map(fields, &validate_single_field(&1, depth))
  end

  defp validate_single_field(field, _depth) when not is_map(field) do
    ["each field must be a map, got: #{inspect(field)}"]
  end

  defp validate_single_field(field, depth) do
    errors = []
    errors = errors ++ validate_field_name(field)
    errors = errors ++ validate_field_type(field)
    errors = errors ++ validate_field_constraints(field)
    errors = errors ++ validate_field_nesting(field, depth)
    errors
  end

  defp validate_field_name(%{"name" => name}) when is_binary(name) do
    if Regex.match?(@field_name_regex, name) do
      []
    else
      ["field name '#{name}' is invalid — must match #{inspect(@field_name_regex.source)}"]
    end
  end

  defp validate_field_name(%{"name" => _}), do: ["field name must be a string"]
  defp validate_field_name(_), do: ["field is missing required key 'name'"]

  defp validate_field_type(%{"type" => type}) when type in @valid_types, do: []

  defp validate_field_type(%{"type" => type}),
    do: ["unknown type '#{type}' — valid types: #{Enum.join(@valid_types, ", ")}"]

  defp validate_field_type(_), do: ["field is missing required key 'type'"]

  defp validate_field_constraints(%{"type" => type, "constraints" => constraints})
       when is_map(constraints) do
    validate_constraints_for_type(type, constraints)
  end

  defp validate_field_constraints(_), do: []

  defp validate_constraints_for_type("string", constraints) do
    errors = check_unknown_keys(constraints, @string_constraints, "string")
    errors = errors ++ validate_string_range(constraints)
    errors = errors ++ validate_pattern(constraints)
    errors = errors ++ validate_enum(constraints)
    errors = errors ++ validate_non_negative(constraints, "min_length")
    errors
  end

  defp validate_constraints_for_type(type, constraints) when type in ~w(integer float) do
    errors = check_unknown_keys(constraints, @number_constraints, type)
    errors = errors ++ validate_number_range(constraints)
    errors
  end

  defp validate_constraints_for_type("boolean", constraints) do
    check_unknown_keys(constraints, [], "boolean")
  end

  defp validate_constraints_for_type("array", constraints) do
    errors = check_unknown_keys(constraints, @array_constraints, "array")

    errors =
      if Map.has_key?(constraints, "item_type") do
        item_type = constraints["item_type"]

        if item_type in @valid_types do
          errors
        else
          errors ++ ["array item_type '#{item_type}' is not a valid type"]
        end
      else
        errors ++ ["array field requires 'item_type' constraint"]
      end

    errors = errors ++ validate_items_range(constraints)
    errors = errors ++ validate_non_negative(constraints, "min_items")
    errors
  end

  defp validate_constraints_for_type("object", constraints) do
    check_unknown_keys(constraints, [], "object")
  end

  defp validate_constraints_for_type(_, _), do: []

  defp check_unknown_keys(constraints, allowed, type) do
    constraints
    |> Map.keys()
    |> Enum.reject(&(&1 in allowed))
    |> Enum.map(&"constraint '#{&1}' is not valid for type '#{type}'")
  end

  defp validate_string_range(constraints) do
    min = Map.get(constraints, "min_length")
    max = Map.get(constraints, "max_length")

    if is_number(min) and is_number(max) and min > max do
      ["min_length (#{min}) cannot be greater than max_length (#{max})"]
    else
      []
    end
  end

  defp validate_number_range(constraints) do
    min = Map.get(constraints, "min")
    max = Map.get(constraints, "max")

    if is_number(min) and is_number(max) and min > max do
      ["min (#{min}) cannot be greater than max (#{max})"]
    else
      []
    end
  end

  defp validate_items_range(constraints) do
    min = Map.get(constraints, "min_items")
    max = Map.get(constraints, "max_items")

    if is_number(min) and is_number(max) and min > max do
      ["min_items (#{min}) cannot be greater than max_items (#{max})"]
    else
      []
    end
  end

  defp validate_non_negative(constraints, key) do
    val = Map.get(constraints, key)

    if is_number(val) and val < 0 do
      ["#{key} cannot be negative"]
    else
      []
    end
  end

  defp validate_pattern(constraints) do
    case Map.get(constraints, "pattern") do
      nil ->
        []

      pattern ->
        case Regex.compile(pattern) do
          {:ok, _} -> []
          {:error, _} -> ["pattern '#{pattern}' is not a valid regex"]
        end
    end
  end

  defp validate_enum(constraints) do
    case Map.get(constraints, "enum") do
      nil ->
        []

      values when is_list(values) ->
        cond do
          values == [] -> ["enum cannot be empty"]
          not Enum.all?(values, &is_binary/1) -> ["enum values must all be strings"]
          true -> []
        end

      _ ->
        ["enum must be a list"]
    end
  end

  defp validate_field_nesting(%{"type" => "object", "fields" => fields}, depth)
       when is_list(fields) do
    if depth + 1 > @max_depth do
      ["nesting depth exceeds maximum of #{@max_depth} levels"]
    else
      validate_fields(fields, depth + 1) ++ check_duplicate_names(fields)
    end
  end

  defp validate_field_nesting(
         %{
           "type" => "array",
           "constraints" => %{"item_type" => "object", "item_fields" => item_fields}
         },
         depth
       )
       when is_list(item_fields) do
    if depth + 1 > @max_depth do
      ["nesting depth exceeds maximum of #{@max_depth} levels"]
    else
      validate_fields(item_fields, depth + 1) ++ check_duplicate_names(item_fields)
    end
  end

  defp validate_field_nesting(_, _), do: []

  defp check_duplicate_names(fields) do
    names =
      fields
      |> Enum.filter(&is_map/1)
      |> Enum.map(& &1["name"])
      |> Enum.filter(&is_binary/1)

    duplicates = names -- Enum.uniq(names)

    duplicates
    |> Enum.uniq()
    |> Enum.map(&"duplicate field name '#{&1}'")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # validate_payload/2
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Validates a runtime payload against a schema definition.

  Returns `{:ok, payload}` or `{:error, [%{field: path, message: msg}]}`.
  """
  @spec validate_payload(map(), list() | nil) ::
          {:ok, map()} | {:error, [%{field: String.t(), message: String.t()}]}
  def validate_payload(payload, nil), do: {:ok, payload}
  def validate_payload(payload, []), do: {:ok, payload}

  def validate_payload(payload, schema) when is_map(payload) and is_list(schema) do
    errors = Enum.flat_map(schema, &validate_field_value(payload, &1, ""))

    case errors do
      [] -> {:ok, payload}
      errors -> {:error, errors}
    end
  end

  defp validate_field_value(payload, field_def, parent_path) do
    name = field_def["name"]
    path = join_path(parent_path, name)
    required = field_def["required"] == true
    present = Map.has_key?(payload, name)
    value = Map.get(payload, name)

    validate_field_presence(value, field_def, path, required, present)
  end

  defp validate_field_presence(_value, _field_def, path, true, false),
    do: [%{field: path, message: "is required"}]

  defp validate_field_presence(nil, _field_def, path, true, true),
    do: [%{field: path, message: "is required and cannot be nil"}]

  defp validate_field_presence("", %{"type" => "string"}, path, true, true),
    do: [%{field: path, message: "is required and cannot be empty"}]

  defp validate_field_presence(_value, _field_def, _path, false, false), do: []
  defp validate_field_presence(nil, _field_def, _path, false, true), do: []

  defp validate_field_presence(value, field_def, path, _required, _present),
    do: validate_typed_value(value, field_def, path)

  defp validate_typed_value(value, %{"type" => "string"} = field_def, path) do
    if is_binary(value) do
      validate_string_constraints(value, field_def["constraints"] || %{}, path)
    else
      [%{field: path, message: "must be a string, got #{type_name(value)}"}]
    end
  end

  defp validate_typed_value(value, %{"type" => "integer"} = field_def, path) do
    if is_integer(value) do
      validate_number_constraints(value, field_def["constraints"] || %{}, path)
    else
      [%{field: path, message: "must be an integer, got #{type_name(value)}"}]
    end
  end

  defp validate_typed_value(value, %{"type" => "float"} = field_def, path) do
    if is_float(value) or is_integer(value) do
      validate_number_constraints(value, field_def["constraints"] || %{}, path)
    else
      [%{field: path, message: "must be a float, got #{type_name(value)}"}]
    end
  end

  defp validate_typed_value(value, %{"type" => "boolean"}, path) do
    if is_boolean(value) do
      []
    else
      [%{field: path, message: "must be a boolean, got #{type_name(value)}"}]
    end
  end

  defp validate_typed_value(value, %{"type" => "array"} = field_def, path) do
    if is_list(value) do
      constraints = field_def["constraints"] || %{}
      errors = validate_array_constraints(value, constraints, path)
      errors = errors ++ validate_array_items(value, constraints, path)
      errors
    else
      [%{field: path, message: "must be an array, got #{type_name(value)}"}]
    end
  end

  defp validate_typed_value(value, %{"type" => "object"} = field_def, path) do
    if is_map(value) do
      nested_fields = field_def["fields"] || []
      Enum.flat_map(nested_fields, &validate_field_value(value, &1, path))
    else
      [%{field: path, message: "must be an object, got #{type_name(value)}"}]
    end
  end

  defp validate_typed_value(_value, _field_def, _path), do: []

  # ── String constraints ──

  defp validate_string_constraints(value, constraints, path) do
    len = String.length(value)

    [
      check_min_length(len, constraints, path),
      check_max_length(len, constraints, path),
      check_pattern(value, constraints, path),
      check_enum(value, constraints, path)
    ]
    |> List.flatten()
  end

  defp check_min_length(len, %{"min_length" => min}, path) when is_number(min) and len < min,
    do: [%{field: path, message: "must be at least #{min} characters"}]

  defp check_min_length(_, _, _), do: []

  defp check_max_length(len, %{"max_length" => max}, path) when is_number(max) and len > max,
    do: [%{field: path, message: "must be at most #{max} characters"}]

  defp check_max_length(_, _, _), do: []

  @regex_timeout_ms 100

  defp check_pattern(value, %{"pattern" => pattern}, path) when is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        safe_regex_match(regex, value, pattern, path)

      _ ->
        []
    end
  end

  defp check_pattern(_, _, _), do: []

  defp safe_regex_match(regex, value, pattern, path) do
    task = Task.async(fn -> Regex.match?(regex, value) end)

    case Task.yield(task, @regex_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, true} ->
        []

      {:ok, false} ->
        [%{field: path, message: "must match pattern '#{pattern}'"}]

      nil ->
        [
          %{
            field: path,
            message: "pattern '#{pattern}' timed out (possible catastrophic backtracking)"
          }
        ]
    end
  end

  defp check_enum(value, %{"enum" => allowed}, path) when is_list(allowed) do
    if value in allowed,
      do: [],
      else: [%{field: path, message: "must be one of: #{Enum.join(allowed, ", ")}"}]
  end

  defp check_enum(_, _, _), do: []

  # ── Number constraints ──

  defp validate_number_constraints(value, constraints, path) do
    errors = []

    errors =
      case Map.get(constraints, "min") do
        nil -> errors
        min when value < min -> errors ++ [%{field: path, message: "must be >= #{min}"}]
        _ -> errors
      end

    errors =
      case Map.get(constraints, "max") do
        nil -> errors
        max when value > max -> errors ++ [%{field: path, message: "must be <= #{max}"}]
        _ -> errors
      end

    errors
  end

  # ── Array constraints ──

  defp validate_array_constraints(value, constraints, path) do
    errors = []

    errors =
      case Map.get(constraints, "min_items") do
        nil ->
          errors

        min when length(value) < min ->
          errors ++ [%{field: path, message: "must have at least #{min} items"}]

        _ ->
          errors
      end

    errors =
      case Map.get(constraints, "max_items") do
        nil ->
          errors

        max when length(value) > max ->
          errors ++ [%{field: path, message: "must have at most #{max} items"}]

        _ ->
          errors
      end

    errors
  end

  defp validate_array_items(value, constraints, path) do
    case Map.get(constraints, "item_type") do
      "object" -> validate_object_items(value, Map.get(constraints, "item_fields", []), path)
      item_type when is_binary(item_type) -> validate_primitive_items(value, item_type, path)
      _ -> []
    end
  end

  defp validate_object_items(value, item_fields, path) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(&validate_single_object_item(&1, item_fields, path))
  end

  defp validate_single_object_item({item, index}, item_fields, path) do
    item_path = "#{path}[#{index}]"

    if is_map(item) do
      Enum.flat_map(item_fields, &validate_field_value(item, &1, item_path))
    else
      [%{field: item_path, message: "must be an object"}]
    end
  end

  defp validate_primitive_items(value, item_type, path) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(&validate_single_primitive_item(&1, item_type, path))
  end

  defp validate_single_primitive_item({item, index}, item_type, path) do
    item_path = "#{path}[#{index}]"

    if matches_type?(item, item_type),
      do: [],
      else: [%{field: item_path, message: "must be a #{item_type}"}]
  end

  defp matches_type?(value, "string"), do: is_binary(value)
  defp matches_type?(value, "integer"), do: is_integer(value)
  defp matches_type?(value, "float"), do: is_float(value) or is_integer(value)
  defp matches_type?(value, "boolean"), do: is_boolean(value)
  defp matches_type?(value, "array"), do: is_list(value)
  defp matches_type?(value, "object"), do: is_map(value)
  defp matches_type?(_, _), do: false

  # ── Path helpers ──

  defp join_path("", name), do: name
  defp join_path(parent, name), do: "#{parent}.#{name}"

  defp type_name(v) when is_binary(v), do: "string"
  defp type_name(v) when is_integer(v), do: "integer"
  defp type_name(v) when is_float(v), do: "float"
  defp type_name(v) when is_boolean(v), do: "boolean"
  defp type_name(v) when is_list(v), do: "array"
  defp type_name(v) when is_map(v), do: "object"
  defp type_name(v), do: inspect(v)

  # ═══════════════════════════════════════════════════════════════════════════
  # build_initial_state/1
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Builds an initial state map from a state schema definition.

  Each field's `initial_value` is used; fields without it default to `nil`.
  """
  @spec build_initial_state(list() | nil) :: map()
  def build_initial_state(nil), do: %{}
  def build_initial_state([]), do: %{}

  def build_initial_state(schema) when is_list(schema) do
    Map.new(schema, fn field ->
      {field["name"], Map.get(field, "initial_value")}
    end)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # build_response/3
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Builds a response map by mapping state variables to response fields.

  Returns `{:ok, response}` or `{:error, errors}` if mapped variables are missing.
  """
  @spec build_response(map(), list(), list() | nil) ::
          {:ok, map()} | {:error, [%{field: String.t(), message: String.t()}]}
  def build_response(_state, _response_schema, nil), do: {:ok, %{}}
  def build_response(_state, _response_schema, []), do: {:ok, %{}}

  def build_response(state, response_schema, mapping) when is_list(mapping) do
    schema_map = Map.new(response_schema || [], fn f -> {f["name"], f} end)

    {response, errors} =
      Enum.reduce(mapping, {%{}, []}, fn entry, {resp, errs} ->
        response_field = entry["response_field"]
        state_variable = entry["state_variable"]

        if Map.has_key?(state, state_variable) do
          value = Map.get(state, state_variable)
          type_errors = validate_mapped_type(value, schema_map, response_field)
          {Map.put(resp, response_field, value), errs ++ type_errors}
        else
          error = %{
            field: response_field,
            message: "state variable '#{state_variable}' not found in state"
          }

          {resp, errs ++ [error]}
        end
      end)

    case errors do
      [] -> {:ok, response}
      errors -> {:error, errors}
    end
  end

  # Validate that a mapped value matches the declared response field type.
  # Nil values are allowed (optional fields may be nil in state).
  defp validate_mapped_type(nil, _schema_map, _field), do: []

  defp validate_mapped_type(value, schema_map, field) do
    case Map.get(schema_map, field) do
      nil ->
        []

      %{"type" => type} ->
        if matches_type?(value, type),
          do: [],
          else: [%{field: field, message: "expected type '#{type}', got #{type_name(value)}"}]
    end
  end
end
