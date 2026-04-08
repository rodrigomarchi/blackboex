defmodule Blackboex.FlowExecutor.CodeValidatorTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.CodeValidator
  alias Blackboex.FlowExecutor.ParsedFlow
  alias Blackboex.FlowExecutor.ParsedNode

  describe "validate/1" do
    test "returns :ok for valid Elixir code" do
      assert :ok = CodeValidator.validate("String.upcase(input)")
    end

    test "returns :ok for multi-line valid code" do
      code = """
      x = input + 1
      x * 2
      """

      assert :ok = CodeValidator.validate(code)
    end

    test "returns {:error, reason} for invalid syntax" do
      assert {:error, reason} = CodeValidator.validate("def foo(")
      assert is_binary(reason)
    end

    test "returns :ok for nil code" do
      assert :ok = CodeValidator.validate(nil)
    end

    test "returns :ok for empty string" do
      assert :ok = CodeValidator.validate("")
    end
  end

  describe "validate_flow/1" do
    test "returns :ok when all nodes have valid code" do
      flow = %ParsedFlow{
        start_node: %ParsedNode{id: "n1", type: :start, position: %{x: 0, y: 0}},
        nodes: [
          %ParsedNode{id: "n1", type: :start, position: %{x: 0, y: 0}},
          %ParsedNode{
            id: "n2",
            type: :elixir_code,
            position: %{x: 100, y: 0},
            data: %{"code" => "String.upcase(input)"}
          },
          %ParsedNode{id: "n3", type: :end, position: %{x: 200, y: 0}}
        ],
        edges: [],
        end_node_ids: ["n3"],
        adjacency: %{}
      }

      assert :ok = CodeValidator.validate_flow(flow)
    end

    test "returns error with node_id for invalid code in elixir_code node" do
      flow = %ParsedFlow{
        start_node: %ParsedNode{id: "n1", type: :start, position: %{x: 0, y: 0}},
        nodes: [
          %ParsedNode{id: "n1", type: :start, position: %{x: 0, y: 0}},
          %ParsedNode{
            id: "n2",
            type: :elixir_code,
            position: %{x: 100, y: 0},
            data: %{"code" => "def foo("}
          },
          %ParsedNode{id: "n3", type: :end, position: %{x: 200, y: 0}}
        ],
        edges: [],
        end_node_ids: ["n3"],
        adjacency: %{}
      }

      assert {:error, [{node_id, field, reason}]} = CodeValidator.validate_flow(flow)
      assert node_id == "n2"
      assert field == "code"
      assert is_binary(reason)
    end

    test "returns error for invalid expression in condition node" do
      flow = %ParsedFlow{
        start_node: %ParsedNode{id: "n1", type: :start, position: %{x: 0, y: 0}},
        nodes: [
          %ParsedNode{id: "n1", type: :start, position: %{x: 0, y: 0}},
          %ParsedNode{
            id: "n2",
            type: :condition,
            position: %{x: 100, y: 0},
            data: %{"expression" => "if true do"}
          },
          %ParsedNode{id: "n3", type: :end, position: %{x: 200, y: 0}}
        ],
        edges: [],
        end_node_ids: ["n3"],
        adjacency: %{}
      }

      assert {:error, [{node_id, field, _reason}]} = CodeValidator.validate_flow(flow)
      assert node_id == "n2"
      assert field == "expression"
    end

    test "skips validation for start and end nodes" do
      flow = %ParsedFlow{
        start_node: %ParsedNode{id: "n1", type: :start, position: %{x: 0, y: 0}},
        nodes: [
          %ParsedNode{id: "n1", type: :start, position: %{x: 0, y: 0}},
          %ParsedNode{id: "n2", type: :end, position: %{x: 100, y: 0}}
        ],
        edges: [],
        end_node_ids: ["n2"],
        adjacency: %{}
      }

      assert :ok = CodeValidator.validate_flow(flow)
    end
  end
end
