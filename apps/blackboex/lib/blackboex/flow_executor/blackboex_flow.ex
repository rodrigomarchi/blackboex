defmodule Blackboex.FlowExecutor.BlackboexFlow do
  @moduledoc """
  Validates the canonical BlackboexFlow JSON format.

  BlackboexFlow is the single source of truth for flow definitions.
  The Drawflow editor converts to/from this format at the JS boundary.
  The server only ever sees BlackboexFlow JSON.

  ## Format

      %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 100, "y" => 200}, "data" => %{...}},
          ...
        ],
        "edges" => [
          %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
          ...
        ]
      }
  """

  alias Blackboex.FlowExecutor.SchemaValidator

  @current_version "1.0"
  @valid_node_types ~w(start elixir_code condition end http_request delay sub_flow for_each webhook_wait fail debug)
  @node_id_format ~r/^n\d+$/

  @spec current_version() :: String.t()
  def current_version, do: @current_version

  @spec validate(map()) :: :ok | {:error, String.t()}
  def validate(%{"version" => version} = definition) when is_binary(version) do
    with :ok <- validate_version(version),
         :ok <- validate_nodes(definition),
         :ok <- validate_edges(definition),
         :ok <- validate_edge_refs(definition),
         :ok <- validate_no_self_loops(definition),
         :ok <- validate_no_duplicate_edges(definition),
         :ok <- validate_source_ports(definition),
         :ok <- validate_no_fan_in(definition),
         :ok <- validate_node_schemas(definition),
         :ok <- validate_skip_conditions(definition) do
      :ok
    end
  end

  def validate(%{}), do: {:error, "missing required field: version"}
  def validate(_), do: {:error, "definition must be a map"}

  # ── Private ──────────────────────────────────────────────────

  defp validate_version(@current_version), do: :ok
  defp validate_version(v), do: {:error, "unsupported version: #{v}"}

  defp validate_nodes(%{"nodes" => nodes}) when is_list(nodes) do
    case validate_each_node(nodes, []) do
      :ok -> validate_node_ids_unique(nodes)
      error -> error
    end
  end

  defp validate_nodes(_), do: {:error, "missing or invalid field: nodes"}

  defp validate_each_node([], _seen), do: :ok

  defp validate_each_node([node | rest], seen) do
    with :ok <- validate_node_shape(node),
         :ok <- validate_node_type(node) do
      validate_each_node(rest, [node["id"] | seen])
    end
  end

  defp validate_node_shape(%{"id" => id, "type" => type, "position" => pos, "data" => _data})
       when is_binary(id) and is_binary(type) and is_map(pos) do
    with :ok <- validate_node_id_format(id) do
      case pos do
        %{"x" => x, "y" => y} when is_number(x) and is_number(y) -> :ok
        _ -> {:error, "node #{id}: position must have numeric x and y"}
      end
    end
  end

  defp validate_node_shape(%{"id" => id}) do
    {:error, "node #{id}: missing required fields (type, position, data)"}
  end

  defp validate_node_shape(_), do: {:error, "node missing required field: id"}

  defp validate_node_id_format(id) do
    if Regex.match?(@node_id_format, id) do
      :ok
    else
      {:error, "node #{id}: id must match format 'n<number>' (e.g. n1, n2)"}
    end
  end

  defp validate_node_type(%{"id" => id, "type" => type}) do
    if type in @valid_node_types do
      :ok
    else
      {:error,
       "node #{id}: invalid type '#{type}', expected one of: #{Enum.join(@valid_node_types, ", ")}"}
    end
  end

  defp validate_node_ids_unique(nodes) do
    ids = Enum.map(nodes, & &1["id"])

    case ids -- Enum.uniq(ids) do
      [] -> :ok
      dupes -> {:error, "duplicate node ids: #{Enum.join(Enum.uniq(dupes), ", ")}"}
    end
  end

  defp validate_edges(%{"edges" => edges}) when is_list(edges) do
    validate_each_edge(edges)
  end

  defp validate_edges(%{"edges" => _}), do: {:error, "edges must be a list"}
  defp validate_edges(_), do: {:error, "missing required field: edges"}

  defp validate_each_edge([]), do: :ok

  defp validate_each_edge([edge | rest]) do
    case validate_edge_shape(edge) do
      :ok -> validate_each_edge(rest)
      error -> error
    end
  end

  defp validate_edge_shape(%{
         "id" => id,
         "source" => s,
         "source_port" => sp,
         "target" => t,
         "target_port" => tp
       })
       when is_binary(id) and is_binary(s) and is_integer(sp) and is_binary(t) and
              is_integer(tp) do
    :ok
  end

  defp validate_edge_shape(%{"id" => id}) do
    {:error, "edge #{id}: missing or invalid fields (source, source_port, target, target_port)"}
  end

  defp validate_edge_shape(_), do: {:error, "edge missing required field: id"}

  defp validate_edge_refs(%{"nodes" => nodes, "edges" => edges}) do
    node_ids = MapSet.new(nodes, & &1["id"])

    Enum.reduce_while(edges, :ok, fn edge, :ok ->
      cond do
        edge["source"] not in node_ids ->
          {:halt,
           {:error, "edge #{edge["id"]}: source '#{edge["source"]}' references non-existent node"}}

        edge["target"] not in node_ids ->
          {:halt,
           {:error, "edge #{edge["id"]}: target '#{edge["target"]}' references non-existent node"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_no_self_loops(%{"edges" => edges}) do
    case Enum.find(edges, fn e -> e["source"] == e["target"] end) do
      nil -> :ok
      edge -> {:error, "edge #{edge["id"]}: self-loop detected (source == target)"}
    end
  end

  defp validate_no_duplicate_edges(%{"edges" => edges}) do
    edge_keys =
      Enum.map(edges, fn e -> {e["source"], e["source_port"], e["target"], e["target_port"]} end)

    case edge_keys -- Enum.uniq(edge_keys) do
      [] ->
        :ok

      [dup | _] ->
        {:error,
         "duplicate edge: #{elem(dup, 0)} port #{elem(dup, 1)} → #{elem(dup, 2)} port #{elem(dup, 3)}"}
    end
  end

  # Condition nodes have dynamic outputs, so only validate fixed-output node types
  @fixed_output_counts %{
    "start" => 1,
    "elixir_code" => 1,
    "end" => 0,
    "fail" => 0,
    "debug" => 1,
    "sub_flow" => 1,
    "http_request" => 1,
    "delay" => 1,
    "for_each" => 1,
    "webhook_wait" => 1
  }

  defp validate_source_ports(%{"nodes" => nodes, "edges" => edges}) do
    node_map = Map.new(nodes, fn n -> {n["id"], n} end)

    Enum.reduce_while(edges, :ok, fn edge, :ok ->
      node = Map.get(node_map, edge["source"])
      validate_edge_source_port(edge, node)
    end)
  end

  defp validate_edge_source_port(_edge, %{"type" => "condition"}), do: {:cont, :ok}

  defp validate_edge_source_port(edge, %{"type" => type} = _node) do
    max_port = Map.get(@fixed_output_counts, type, 1) - 1

    if edge["source_port"] > max_port do
      {:halt,
       {:error,
        "edge #{edge["id"]}: source_port #{edge["source_port"]} exceeds max port #{max_port} for #{type} node #{edge["source"]}"}}
    else
      {:cont, :ok}
    end
  end

  defp validate_no_fan_in(%{"edges" => edges}) do
    # Each node input port can receive at most one incoming edge
    target_ports = Enum.map(edges, fn e -> {e["target"], e["target_port"]} end)

    case target_ports -- Enum.uniq(target_ports) do
      [] ->
        :ok

      [dup | _] ->
        {:error,
         "node #{elem(dup, 0)} port #{elem(dup, 1)}: multiple incoming edges (fan-in not supported)"}
    end
  end

  # ── skip_condition validation ────────────────────────────────

  defp validate_skip_conditions(%{"nodes" => nodes}) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      skip_cond = get_in(node, ["data", "skip_condition"])

      if not is_nil(skip_cond) and not is_binary(skip_cond) do
        {:halt, {:error, "node #{node["id"]}: skip_condition must be a string"}}
      else
        {:cont, :ok}
      end
    end)
  end

  # ── Node schema validation ──────────────────────────────────

  defp validate_node_schemas(%{"nodes" => nodes}) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case validate_single_node_schema(node) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_single_node_schema(%{"id" => id, "type" => "start", "data" => data}) do
    with :ok <- validate_optional_schema(data, "payload_schema", id),
         :ok <- validate_optional_schema(data, "state_schema", id) do
      :ok
    end
  end

  defp validate_single_node_schema(%{"id" => id, "type" => "end", "data" => data}) do
    with :ok <- validate_optional_schema(data, "response_schema", id),
         :ok <- validate_response_mapping(data, id) do
      :ok
    end
  end

  defp validate_single_node_schema(%{"id" => id, "type" => "http_request", "data" => data}) do
    with :ok <- validate_required_string(data, "url", id),
         :ok <- validate_http_method(data, id),
         :ok <- validate_optional_map(data, "headers", id),
         :ok <- validate_optional_string(data, "body_template", id),
         :ok <- validate_optional_positive_integer(data, "timeout_ms", id),
         :ok <- validate_optional_non_negative_integer(data, "max_retries", id),
         :ok <- validate_optional_enum(data, "auth_type", ~w(none bearer basic api_key), id),
         :ok <- validate_optional_map(data, "auth_config", id),
         :ok <- validate_optional_integer_list(data, "expected_status", id),
         :ok <- validate_optional_map(data, "undo_config", id) do
      :ok
    end
  end

  defp validate_single_node_schema(%{"id" => id, "type" => "delay", "data" => data}) do
    with :ok <- validate_required_positive_integer(data, "duration_ms", id),
         :ok <- validate_optional_positive_integer(data, "max_duration_ms", id) do
      :ok
    end
  end

  defp validate_single_node_schema(%{"id" => id, "type" => "for_each", "data" => data}) do
    with :ok <- validate_required_string(data, "source_expression", id),
         :ok <- validate_required_string(data, "body_code", id),
         :ok <- validate_optional_identifier(data, "item_variable", id),
         :ok <- validate_optional_identifier(data, "accumulator", id),
         :ok <- validate_optional_batch_size(data, "batch_size", id),
         :ok <- validate_optional_positive_integer(data, "timeout_ms", id) do
      :ok
    end
  end

  defp validate_single_node_schema(%{"id" => id, "type" => "debug", "data" => data}) do
    with :ok <- validate_optional_string(data, "expression", id),
         :ok <- validate_optional_enum(data, "log_level", ~w(debug info warning), id),
         :ok <- validate_optional_identifier(data, "state_key", id) do
      :ok
    end
  end

  defp validate_single_node_schema(%{"id" => id, "type" => "webhook_wait", "data" => data}) do
    with :ok <- validate_required_string(data, "event_type", id),
         :ok <- validate_optional_positive_integer(data, "timeout_ms", id),
         :ok <- validate_optional_string(data, "resume_path", id) do
      :ok
    end
  end

  defp validate_single_node_schema(%{"id" => id, "type" => "sub_flow", "data" => data}) do
    with :ok <- validate_optional_string(data, "flow_id", id),
         :ok <- validate_optional_map(data, "input_mapping", id),
         :ok <- validate_optional_positive_integer(data, "timeout_ms", id) do
      :ok
    end
  end

  defp validate_single_node_schema(%{"id" => id, "type" => "fail", "data" => data}) do
    with :ok <- validate_required_string(data, "message", id),
         :ok <- validate_optional_boolean(data, "include_state", id) do
      :ok
    end
  end

  defp validate_single_node_schema(%{"id" => id, "type" => "elixir_code", "data" => data}) do
    with :ok <- validate_optional_string(data, "code", id),
         :ok <- validate_optional_string(data, "undo_code", id),
         :ok <- validate_optional_positive_integer(data, "timeout_ms", id) do
      :ok
    end
  end

  defp validate_single_node_schema(_node), do: :ok

  # ── Node data field validators ──────────────────────────────

  defp validate_required_string(data, key, node_id) do
    case Map.get(data, key) do
      val when is_binary(val) and byte_size(val) > 0 -> :ok
      nil -> {:error, "node #{node_id}: missing required field: #{key}"}
      "" -> {:error, "node #{node_id}: #{key} must be a non-empty string"}
      _ -> {:error, "node #{node_id}: #{key} must be a string"}
    end
  end

  defp validate_optional_string(data, key, node_id) do
    case Map.get(data, key) do
      nil -> :ok
      val when is_binary(val) -> :ok
      _ -> {:error, "node #{node_id}: #{key} must be a string"}
    end
  end

  defp validate_optional_map(data, key, node_id) do
    case Map.get(data, key) do
      nil -> :ok
      val when is_map(val) -> :ok
      _ -> {:error, "node #{node_id}: #{key} must be a map"}
    end
  end

  defp validate_optional_positive_integer(data, key, node_id) do
    case Map.get(data, key) do
      nil -> :ok
      val when is_integer(val) and val > 0 -> :ok
      _ -> {:error, "node #{node_id}: #{key} must be a positive integer"}
    end
  end

  defp validate_required_positive_integer(data, key, node_id) do
    case Map.get(data, key) do
      val when is_integer(val) and val > 0 -> :ok
      nil -> {:error, "node #{node_id}: missing required field: #{key}"}
      _ -> {:error, "node #{node_id}: #{key} must be a positive integer"}
    end
  end

  defp validate_optional_non_negative_integer(data, key, node_id) do
    case Map.get(data, key) do
      nil -> :ok
      val when is_integer(val) and val >= 0 -> :ok
      _ -> {:error, "node #{node_id}: #{key} must be a non-negative integer"}
    end
  end

  defp validate_optional_enum(data, key, allowed, node_id) do
    case Map.get(data, key) do
      nil ->
        :ok

      val when is_binary(val) ->
        if val in allowed do
          :ok
        else
          {:error, "node #{node_id}: #{key} must be one of: #{Enum.join(allowed, ", ")}"}
        end

      _ ->
        {:error, "node #{node_id}: #{key} must be a string"}
    end
  end

  defp validate_optional_integer_list(data, key, node_id) do
    case Map.get(data, key) do
      nil ->
        :ok

      val when is_list(val) ->
        if Enum.all?(val, &is_integer/1) do
          :ok
        else
          {:error, "node #{node_id}: #{key} must be a list of integers"}
        end

      _ ->
        {:error, "node #{node_id}: #{key} must be a list"}
    end
  end

  @identifier_format ~r/^\w+$/

  defp validate_optional_identifier(data, key, node_id) do
    case Map.get(data, key) do
      nil ->
        :ok

      val when is_binary(val) ->
        if Regex.match?(@identifier_format, val) do
          :ok
        else
          {:error,
           "node #{node_id}: #{key} must contain only alphanumeric characters and underscores"}
        end

      _ ->
        {:error, "node #{node_id}: #{key} must be a string"}
    end
  end

  defp validate_optional_boolean(data, key, node_id) do
    case Map.get(data, key) do
      nil -> :ok
      val when is_boolean(val) -> :ok
      _ -> {:error, "node #{node_id}: #{key} must be a boolean"}
    end
  end

  defp validate_optional_batch_size(data, key, node_id) do
    case Map.get(data, key) do
      nil -> :ok
      val when is_integer(val) and val >= 1 and val <= 100 -> :ok
      _ -> {:error, "node #{node_id}: #{key} must be an integer between 1 and 100"}
    end
  end

  defp validate_http_method(data, node_id) do
    valid_methods = ~w(GET POST PUT PATCH DELETE)

    case Map.get(data, "method") do
      val when is_binary(val) ->
        if val in valid_methods do
          :ok
        else
          {:error, "node #{node_id}: method must be one of: #{Enum.join(valid_methods, ", ")}"}
        end

      nil ->
        {:error, "node #{node_id}: missing required field: method"}

      _ ->
        {:error, "node #{node_id}: method must be a string"}
    end
  end

  defp validate_optional_schema(data, key, node_id) do
    case Map.get(data, key) do
      nil ->
        :ok

      [] ->
        :ok

      schema when is_list(schema) ->
        case SchemaValidator.validate_schema_definition(schema) do
          :ok ->
            :ok

          {:error, errors} ->
            {:error, "node #{node_id}: invalid #{key} — #{Enum.join(errors, "; ")}"}
        end

      _ ->
        {:error, "node #{node_id}: #{key} must be a list"}
    end
  end

  defp validate_response_mapping(data, node_id) do
    mapping = Map.get(data, "response_mapping")
    response_schema = Map.get(data, "response_schema")

    cond do
      is_nil(mapping) or mapping == [] ->
        :ok

      is_nil(response_schema) or response_schema == [] ->
        {:error, "node #{node_id}: response_mapping requires response_schema to be defined"}

      is_list(mapping) ->
        validate_mapping_fields(mapping, response_schema, node_id)

      true ->
        {:error, "node #{node_id}: response_mapping must be a list"}
    end
  end

  defp validate_mapping_fields(mapping, response_schema, node_id) do
    schema_field_names = MapSet.new(response_schema, & &1["name"])
    response_fields = Enum.map(mapping, & &1["response_field"])
    duplicates = response_fields -- Enum.uniq(response_fields)

    if duplicates != [] do
      {:error,
       "node #{node_id}: duplicate response_field in mapping: #{Enum.join(Enum.uniq(duplicates), ", ")}"}
    else
      case Enum.find(response_fields, &(&1 not in schema_field_names)) do
        nil ->
          :ok

        missing ->
          {:error, "node #{node_id}: response_mapping references non-existent field '#{missing}'"}
      end
    end
  end
end
