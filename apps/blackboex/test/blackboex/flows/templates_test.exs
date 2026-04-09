defmodule Blackboex.Flows.TemplatesTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.{BlackboexFlow, CodeValidator, DefinitionParser}
  alias Blackboex.Flows.Templates

  # Ensure DefinitionParser module is loaded so its @known_types atoms exist
  Code.ensure_loaded!(DefinitionParser)

  describe "list/0" do
    test "returns all templates" do
      templates = Templates.list()
      assert [_ | _] = templates
      assert Enum.all?(templates, &is_map/1)
    end

    test "each template has required fields" do
      for t <- Templates.list() do
        assert is_binary(t.id)
        assert is_binary(t.name)
        assert is_binary(t.description)
        assert is_binary(t.category)
        assert is_binary(t.icon)
        assert is_map(t.definition)
      end
    end
  end

  describe "get/1" do
    test "returns hello_world template" do
      template = Templates.get("hello_world")
      assert template != nil
      assert template.id == "hello_world"
      assert template.name == "Hello World"
    end

    test "returns nil for unknown id" do
      assert Templates.get("nonexistent") == nil
    end
  end

  describe "list_by_category/0" do
    test "returns templates grouped by category" do
      grouped = Templates.list_by_category()
      assert is_list(grouped)

      for {category, templates} <- grouped do
        assert is_binary(category)
        assert is_list(templates)
        assert [_ | _] = templates
      end
    end
  end

  describe "hello_world template validation" do
    setup do
      %{template: Templates.get("hello_world")}
    end

    test "definition passes BlackboexFlow.validate/1", %{template: t} do
      assert :ok = BlackboexFlow.validate(t.definition)
    end

    test "definition passes DefinitionParser.parse/1", %{template: t} do
      assert {:ok, parsed} = DefinitionParser.parse(t.definition)
      assert parsed.start_node.type == :start
      assert length(parsed.end_node_ids) == 3
      # 1 start + 5 elixir_code + 1 condition + 3 end = 10
      assert length(parsed.nodes) == 10
      assert length(parsed.edges) == 9
    end

    test "definition passes CodeValidator.validate_flow/1", %{template: t} do
      {:ok, parsed} = DefinitionParser.parse(t.definition)
      assert :ok = CodeValidator.validate_flow(parsed)
    end

    test "has correct node types", %{template: t} do
      nodes = t.definition["nodes"]
      types = Enum.map(nodes, & &1["type"]) |> Enum.sort()

      assert types == [
               "condition",
               "elixir_code",
               "elixir_code",
               "elixir_code",
               "elixir_code",
               "elixir_code",
               "end",
               "end",
               "end",
               "start"
             ]
    end

    test "condition node has 3-way branching", %{template: t} do
      condition = Enum.find(t.definition["nodes"], &(&1["type"] == "condition"))
      assert condition != nil

      # Edges from condition should use ports 0, 1, 2
      condition_edges =
        t.definition["edges"]
        |> Enum.filter(&(&1["source"] == condition["id"]))
        |> Enum.map(& &1["source_port"])
        |> Enum.sort()

      assert condition_edges == [0, 1, 2]
    end
  end

  describe "hello_world template — schema features" do
    setup do
      %{template: Templates.get("hello_world")}
    end

    test "start node has payload_schema with name (required), email, phone", %{template: t} do
      start = Enum.find(t.definition["nodes"], &(&1["type"] == "start"))
      schema = start["data"]["payload_schema"]

      assert is_list(schema)
      assert length(schema) == 3

      names = Enum.map(schema, & &1["name"])
      assert "name" in names
      assert "email" in names
      assert "phone" in names

      name_field = Enum.find(schema, &(&1["name"] == "name"))
      assert name_field["required"] == true
      assert name_field["type"] == "string"
      assert name_field["constraints"]["min_length"] == 1
    end

    test "start node has state_schema with 5 variables", %{template: t} do
      start = Enum.find(t.definition["nodes"], &(&1["type"] == "start"))
      schema = start["data"]["state_schema"]

      assert is_list(schema)
      assert length(schema) == 5

      names = Enum.map(schema, & &1["name"])
      assert "greeting" in names
      assert "contact_type" in names
      assert "email" in names
      assert "phone" in names
      assert "delivered_via" in names
    end

    test "state_schema fields have initial values", %{template: t} do
      start = Enum.find(t.definition["nodes"], &(&1["type"] == "start"))
      schema = start["data"]["state_schema"]

      greeting = Enum.find(schema, &(&1["name"] == "greeting"))
      assert greeting["initial_value"] == ""

      contact_type = Enum.find(schema, &(&1["name"] == "contact_type"))
      assert contact_type["initial_value"] == "none"

      delivered_via = Enum.find(schema, &(&1["name"] == "delivered_via"))
      assert delivered_via["initial_value"] == ""
    end

    test "end (email) node has response_schema and response_mapping", %{template: t} do
      end_email = Enum.find(t.definition["nodes"], &(&1["id"] == "n8"))
      schema = end_email["data"]["response_schema"]
      mapping = end_email["data"]["response_mapping"]

      assert is_list(schema)
      assert length(schema) == 3
      assert Enum.map(schema, & &1["name"]) == ["channel", "to", "message"]

      assert is_list(mapping)
      assert length(mapping) == 3
    end

    test "end (phone) node has response_schema and response_mapping", %{template: t} do
      end_phone = Enum.find(t.definition["nodes"], &(&1["id"] == "n9"))
      schema = end_phone["data"]["response_schema"]
      mapping = end_phone["data"]["response_mapping"]

      assert is_list(schema)
      assert length(schema) == 3
      assert is_list(mapping)
      assert length(mapping) == 3
    end

    test "end (error) node has no response_schema (pass-through)", %{template: t} do
      end_error = Enum.find(t.definition["nodes"], &(&1["id"] == "n10"))
      refute Map.has_key?(end_error["data"], "response_schema")
      refute Map.has_key?(end_error["data"], "response_mapping")
    end

    test "response_mapping fields reference existing state_schema variable names", %{template: t} do
      start = Enum.find(t.definition["nodes"], &(&1["type"] == "start"))
      state_names = MapSet.new(start["data"]["state_schema"], & &1["name"])

      for node <- t.definition["nodes"],
          node["type"] == "end",
          mapping = node["data"]["response_mapping"],
          is_list(mapping),
          entry <- mapping do
        assert entry["state_variable"] in state_names,
               "End node #{node["id"]}: state_variable '#{entry["state_variable"]}' not in state_schema"
      end
    end

    test "definition still passes BlackboexFlow.validate/1 with schemas", %{template: t} do
      assert :ok = BlackboexFlow.validate(t.definition)
    end

    test "definition still passes DefinitionParser.parse/1 with schemas", %{template: t} do
      assert {:ok, parsed} = DefinitionParser.parse(t.definition)
      assert parsed.start_node.type == :start
    end
  end
end
