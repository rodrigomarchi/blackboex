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
end
