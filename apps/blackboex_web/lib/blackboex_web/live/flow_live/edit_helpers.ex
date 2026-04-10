defmodule BlackboexWeb.FlowLive.EditHelpers do
  @moduledoc """
  Pure helper functions for the flow editor LiveView.
  Contains node type definitions, schema manipulation logic,
  field parsing, and state variable extraction.
  """

  @node_types [
    %{
      type: "start",
      label: "Start",
      subtitle: "Trigger",
      icon: "hero-play",
      color: "#10b981",
      inputs: 0,
      outputs: 1,
      group: "flow"
    },
    %{
      type: "elixir_code",
      label: "Elixir Code",
      subtitle: "Run Elixir code",
      icon: "hero-code-bracket",
      color: "#8b5cf6",
      inputs: 1,
      outputs: 1,
      group: "logic"
    },
    %{
      type: "condition",
      label: "Condition",
      subtitle: "Dynamic branches",
      icon: "hero-arrows-right-left",
      color: "#3b82f6",
      inputs: 1,
      outputs: 3,
      group: "logic"
    },
    %{
      type: "end",
      label: "End",
      subtitle: "Stop flow",
      icon: "hero-stop",
      color: "#6b7280",
      inputs: 1,
      outputs: 0,
      group: "flow"
    },
    %{
      type: "http_request",
      label: "HTTP Request",
      subtitle: "Call API",
      icon: "hero-globe-alt",
      color: "#f97316",
      inputs: 1,
      outputs: 1,
      group: "integration"
    },
    %{
      type: "delay",
      label: "Delay",
      subtitle: "Wait",
      icon: "hero-clock",
      color: "#eab308",
      inputs: 1,
      outputs: 1,
      group: "control"
    },
    %{
      type: "webhook_wait",
      label: "Webhook Wait",
      subtitle: "Pause for event",
      icon: "hero-arrow-path",
      color: "#ec4899",
      inputs: 1,
      outputs: 1,
      group: "control"
    },
    %{
      type: "sub_flow",
      label: "Sub-Flow",
      subtitle: "Nested flow",
      icon: "hero-squares-2x2",
      color: "#6366f1",
      inputs: 1,
      outputs: 1,
      group: "composition"
    },
    %{
      type: "for_each",
      label: "For Each",
      subtitle: "Iterate list",
      icon: "hero-arrow-path-rounded-square",
      color: "#14b8a6",
      inputs: 1,
      outputs: 1,
      group: "composition"
    },
    %{
      type: "fail",
      label: "Fail",
      subtitle: "Error exit",
      icon: "hero-x-circle",
      color: "#ef4444",
      inputs: 1,
      outputs: 0,
      group: "control"
    },
    %{
      type: "debug",
      label: "Debug",
      subtitle: "Inspect data",
      icon: "hero-bug-ant",
      color: "#a855f7",
      inputs: 1,
      outputs: 1,
      group: "logic"
    }
  ]

  @node_type_map Map.new(@node_types, fn n -> {n.type, n} end)

  # Maps synthetic auth form fields to nested auth_config keys
  @auth_field_map %{
    "auth_token" => {"auth_config", "token"},
    "auth_username" => {"auth_config", "username"},
    "auth_password" => {"auth_config", "password"},
    "auth_key_name" => {"auth_config", "key_name"},
    "auth_key_value" => {"auth_config", "key_value"}
  }

  # Maps synthetic undo form fields to nested undo_config keys
  @undo_field_map %{
    "undo_method" => {"undo_config", "method"},
    "undo_url" => {"undo_config", "url"}
  }

  # ── Node type data ─────────────────────────────────────────────────────

  @spec node_types() :: [map()]
  def node_types, do: @node_types

  @spec node_type_map() :: %{String.t() => map()}
  def node_type_map, do: @node_type_map

  # ── Field update helpers ───────────────────────────────────────────────

  @spec apply_field_update(map(), String.t(), any()) :: map()
  def apply_field_update(data, field, value) do
    nested_map = Map.merge(@auth_field_map, @undo_field_map)

    case Map.get(nested_map, field) do
      {parent_key, nested_key} ->
        parent = Map.get(data, parent_key, %{})
        Map.put(data, parent_key, Map.put(parent, nested_key, value))

      nil ->
        Map.put(data, field, coerce_field_value(field, value))
    end
  end

  @spec coerce_field_value(String.t(), any()) :: any()
  def coerce_field_value("include_state", value), do: value == "true"
  def coerce_field_value(_field, value), do: value

  # ── Schema path helpers ────────────────────────────────────────────────

  @spec apply_at_path(list(), String.t(), (list() -> list())) :: list()
  def apply_at_path(fields, "", update_fn), do: update_fn.(fields)

  def apply_at_path(fields, path, update_fn) do
    segments = String.split(path, ".")
    do_apply_at_path(fields, segments, update_fn)
  end

  defp do_apply_at_path(fields, [], update_fn), do: update_fn.(fields)

  defp do_apply_at_path(fields, [segment | rest], update_fn) when is_list(fields) do
    case Integer.parse(segment) do
      {index, ""} ->
        List.update_at(fields, index, fn field ->
          do_apply_at_path(field, rest, update_fn)
        end)

      _ ->
        fields
    end
  end

  defp do_apply_at_path(%{} = map, [key | rest], update_fn) do
    current = Map.get(map, key, [])
    Map.put(map, key, do_apply_at_path(current, rest, update_fn))
  end

  defp do_apply_at_path(other, _segments, _update_fn), do: other

  @spec split_path(String.t()) :: {String.t(), non_neg_integer()}
  def split_path(path) do
    parts = String.split(path, ".")
    index = parts |> List.last() |> String.to_integer()
    parent = parts |> Enum.drop(-1) |> Enum.join(".")
    {parent, index}
  end

  # ── Field property helpers ─────────────────────────────────────────────

  @spec update_field_prop(map(), String.t(), any()) :: map()
  def update_field_prop(field, prop, value) do
    parsed_value = parse_field_prop(prop, value, field)
    field = Map.put(field, prop, parsed_value)

    if prop == "type" do
      field
      |> Map.put("constraints", default_constraints(parsed_value))
      |> maybe_remove_fields(parsed_value)
    else
      field
    end
  end

  @spec update_field_constraint(map(), String.t(), any()) :: map()
  def update_field_constraint(field, prop, value) do
    constraints = field["constraints"] || %{}
    parsed = parse_constraint_value(prop, value)

    constraints =
      if parsed == nil or parsed == "" do
        Map.delete(constraints, prop)
      else
        Map.put(constraints, prop, parsed)
      end

    Map.put(field, "constraints", constraints)
  end

  @spec upsert_mapping(list(), String.t(), String.t()) :: list()
  def upsert_mapping(mapping, response_field, "") do
    Enum.reject(mapping, &(&1["response_field"] == response_field))
  end

  def upsert_mapping(mapping, response_field, state_var) do
    entry = %{"response_field" => response_field, "state_variable" => state_var}

    case Enum.find_index(mapping, &(&1["response_field"] == response_field)) do
      nil -> mapping ++ [entry]
      idx -> List.replace_at(mapping, idx, entry)
    end
  end

  defp parse_field_prop("required", "true", _field), do: true
  defp parse_field_prop("required", "false", _field), do: false

  defp parse_field_prop("initial_value", value, %{"type" => "integer"}) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_field_prop("initial_value", value, %{"type" => "float"}) do
    case Float.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_field_prop("initial_value", "true", %{"type" => "boolean"}), do: true
  defp parse_field_prop("initial_value", "false", %{"type" => "boolean"}), do: false

  defp parse_field_prop("initial_value", value, %{"type" => type})
       when type in ["array", "object"] do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      _ -> nil
    end
  end

  defp parse_field_prop(_prop, value, _field), do: value

  defp parse_constraint_value(prop, value)
       when prop in ~w(min_length max_length min_items max_items) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_constraint_value(prop, value) when prop in ~w(min max) do
    case Float.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_constraint_value("enum", value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_constraint_value(_prop, value), do: value

  defp default_constraints("array"), do: %{"item_type" => "string"}
  defp default_constraints(_), do: %{}

  defp maybe_remove_fields(field, type) when type in ~w(string integer float boolean array) do
    Map.delete(field, "fields")
  end

  defp maybe_remove_fields(field, _type), do: field

  # ── State variable helpers ─────────────────────────────────────────────

  @spec get_state_variables(map(), map() | nil) :: [String.t()]
  def get_state_variables(flow, selected_node) do
    case selected_node do
      %{type: "start", data: %{"state_schema" => schema}} when is_list(schema) ->
        extract_variable_names(schema)

      _ ->
        extract_state_variables_from_definition(flow.definition)
    end
  end

  defp extract_state_variables_from_definition(%{"nodes" => nodes}) when is_list(nodes) do
    nodes
    |> Enum.find(&(&1["type"] == "start"))
    |> case do
      %{"data" => %{"state_schema" => schema}} when is_list(schema) ->
        extract_variable_names(schema)

      _ ->
        []
    end
  end

  defp extract_state_variables_from_definition(_), do: []

  defp extract_variable_names(schema) do
    schema |> Enum.map(& &1["name"]) |> Enum.filter(&is_binary/1)
  end

  # ── Confirm dialog helpers ─────────────────────────────────────────────

  @spec build_confirm(String.t() | nil, map()) :: map() | nil
  def build_confirm("regenerate_token", _params) do
    %{
      title: "Regenerate webhook token?",
      description:
        "The current webhook URL will immediately stop working. Any integrations using it will need to be updated.",
      variant: :warning,
      confirm_label: "Regenerate",
      event: "regenerate_token",
      meta: %{}
    }
  end

  def build_confirm(_, _), do: nil
end
