defmodule Blackboex.FlowExecutor.DefinitionParserTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.DefinitionParser
  alias Blackboex.FlowExecutor.ParsedFlow
  alias Blackboex.FlowExecutor.ParsedNode

  @linear_flow %{
    "version" => "1.0",
    "nodes" => [
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 100, "y" => 200},
        "data" => %{"execution_mode" => "sync", "timeout_ms" => 30_000}
      },
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 350, "y" => 200},
        "data" => %{"code" => "String.upcase(input)", "timeout_ms" => 5000}
      },
      %{
        "id" => "n3",
        "type" => "end",
        "position" => %{"x" => 600, "y" => 200},
        "data" => %{}
      }
    ],
    "edges" => [
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0}
    ]
  }

  @branching_flow %{
    "version" => "1.0",
    "nodes" => [
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 0, "y" => 0},
        "data" => %{}
      },
      %{
        "id" => "n2",
        "type" => "condition",
        "position" => %{"x" => 200, "y" => 0},
        "data" => %{"expression" => "input > 0"}
      },
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 400, "y" => -100},
        "data" => %{"code" => "input + 1"}
      },
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 400, "y" => 100},
        "data" => %{"code" => "input - 1"}
      },
      %{
        "id" => "n5",
        "type" => "end",
        "position" => %{"x" => 600, "y" => 0},
        "data" => %{}
      }
    ],
    "edges" => [
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0},
      %{"id" => "e3", "source" => "n2", "source_port" => 1, "target" => "n4", "target_port" => 0},
      %{"id" => "e4", "source" => "n3", "source_port" => 0, "target" => "n5", "target_port" => 0},
      %{"id" => "e5", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0}
    ]
  }

  describe "parse/1 with valid flows" do
    test "parses a linear flow (start -> code -> end)" do
      assert {:ok, %ParsedFlow{} = flow} = DefinitionParser.parse(@linear_flow)

      assert length(flow.nodes) == 3
      assert length(flow.edges) == 2
      assert flow.start_node.id == "n1"
      assert flow.start_node.type == :start
      assert flow.end_node_ids == ["n3"]
    end

    test "parses a branching flow (start -> condition -> two code -> end)" do
      assert {:ok, %ParsedFlow{} = flow} = DefinitionParser.parse(@branching_flow)

      assert length(flow.nodes) == 5
      assert flow.start_node.id == "n1"
      assert flow.end_node_ids == ["n5"]
    end

    test "preserves start node data (execution_mode, timeout_ms)" do
      assert {:ok, %ParsedFlow{start_node: start}} = DefinitionParser.parse(@linear_flow)

      assert start.data == %{"execution_mode" => "sync", "timeout_ms" => 30_000}
    end

    test "builds adjacency map correctly" do
      assert {:ok, %ParsedFlow{adjacency: adj}} = DefinitionParser.parse(@linear_flow)

      assert Map.has_key?(adj, "n1")
      assert "n2" in adj["n1"]
      assert "n3" in adj["n2"]
      refute Map.has_key?(adj, "n3")
    end

    test "node types are atoms" do
      assert {:ok, %ParsedFlow{nodes: nodes}} = DefinitionParser.parse(@linear_flow)

      assert Enum.all?(nodes, fn %ParsedNode{type: t} -> is_atom(t) end)
    end

    test "edges have atom keys" do
      assert {:ok, %ParsedFlow{edges: [edge | _]}} = DefinitionParser.parse(@linear_flow)

      assert is_binary(edge.id)
      assert is_binary(edge.source)
      assert is_integer(edge.source_port)
    end
  end

  describe "parse/1 error: start node" do
    test "returns error when no start node" do
      flow =
        put_in(@linear_flow["nodes"], [
          %{
            "id" => "n1",
            "type" => "elixir_code",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{"code" => "1"}
          },
          %{"id" => "n2", "type" => "end", "position" => %{"x" => 100, "y" => 0}, "data" => %{}}
        ])

      assert {:error, :no_start_node} = DefinitionParser.parse(flow)
    end

    test "returns error when multiple start nodes" do
      flow =
        put_in(@linear_flow["nodes"], [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "start",
            "position" => %{"x" => 100, "y" => 0},
            "data" => %{}
          },
          %{"id" => "n3", "type" => "end", "position" => %{"x" => 200, "y" => 0}, "data" => %{}}
        ])

      assert {:error, :multiple_start_nodes} = DefinitionParser.parse(flow)
    end
  end

  describe "parse/1 error: end node" do
    test "returns error when no end node" do
      flow =
        put_in(@linear_flow["nodes"], [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 100, "y" => 0},
            "data" => %{"code" => "1"}
          }
        ])

      assert {:error, :no_end_node} = DefinitionParser.parse(flow)
    end
  end

  describe "parse/1 error: cycle detected" do
    test "returns error when cycle exists (A -> B -> A)" do
      flow = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 100, "y" => 0},
            "data" => %{"code" => "1"}
          },
          %{
            "id" => "n3",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"code" => "2"}
          },
          %{"id" => "n4", "type" => "end", "position" => %{"x" => 300, "y" => 0}, "data" => %{}}
        ],
        "edges" => [
          %{
            "id" => "e1",
            "source" => "n1",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          },
          %{
            "id" => "e2",
            "source" => "n2",
            "source_port" => 0,
            "target" => "n3",
            "target_port" => 0
          },
          %{
            "id" => "e3",
            "source" => "n3",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          },
          %{
            "id" => "e4",
            "source" => "n3",
            "source_port" => 1,
            "target" => "n4",
            "target_port" => 0
          }
        ]
      }

      assert {:error, {:cycle_detected, _node_id}} = DefinitionParser.parse(flow)
    end
  end

  describe "parse/1 error: orphan nodes" do
    test "returns error when node is not reachable from start" do
      flow = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 100, "y" => 0},
            "data" => %{"code" => "1"}
          },
          %{"id" => "n3", "type" => "end", "position" => %{"x" => 200, "y" => 0}, "data" => %{}},
          %{
            "id" => "orphan",
            "type" => "elixir_code",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{"code" => "2"}
          }
        ],
        "edges" => [
          %{
            "id" => "e1",
            "source" => "n1",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          },
          %{
            "id" => "e2",
            "source" => "n2",
            "source_port" => 0,
            "target" => "n3",
            "target_port" => 0
          }
        ]
      }

      assert {:error, {:orphan_nodes, orphans}} = DefinitionParser.parse(flow)
      assert "orphan" in orphans
    end
  end
end
