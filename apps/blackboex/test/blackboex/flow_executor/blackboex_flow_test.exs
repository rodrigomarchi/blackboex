defmodule Blackboex.FlowExecutor.BlackboexFlowTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.BlackboexFlow

  @valid_flow %{
    "version" => "1.0",
    "nodes" => [
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 100, "y" => 200},
        "data" => %{"name" => "Start", "execution_mode" => "sync"}
      },
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 350, "y" => 200},
        "data" => %{"name" => "Transform", "code" => "String.upcase(input)"}
      },
      %{
        "id" => "n3",
        "type" => "end",
        "position" => %{"x" => 600, "y" => 200},
        "data" => %{"name" => "End"}
      }
    ],
    "edges" => [
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0}
    ]
  }

  describe "validate/1" do
    test "returns :ok for a valid flow" do
      assert :ok = BlackboexFlow.validate(@valid_flow)
    end

    test "returns :ok for a flow with no edges (disconnected nodes)" do
      flow = %{@valid_flow | "edges" => []}
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "returns :ok for a flow with condition node" do
      flow =
        put_in(@valid_flow["nodes"], [
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
            "data" => %{"expression" => "if input, do: 0, else: 1"}
          },
          %{
            "id" => "n3",
            "type" => "end",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{}
          }
        ])

      assert :ok = BlackboexFlow.validate(flow)
    end

    test "rejects missing version" do
      flow = Map.delete(@valid_flow, "version")
      assert {:error, "missing required field: version"} = BlackboexFlow.validate(flow)
    end

    test "rejects unsupported version" do
      flow = %{@valid_flow | "version" => "2.0"}
      assert {:error, "unsupported version: 2.0"} = BlackboexFlow.validate(flow)
    end

    test "rejects missing nodes" do
      flow = Map.delete(@valid_flow, "nodes")
      assert {:error, "missing or invalid field: nodes"} = BlackboexFlow.validate(flow)
    end

    test "rejects non-list nodes" do
      flow = %{@valid_flow | "nodes" => "not a list"}
      assert {:error, "missing or invalid field: nodes"} = BlackboexFlow.validate(flow)
    end

    test "rejects node without id" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{"type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}}
        ])

      assert {:error, "node missing required field: id"} = BlackboexFlow.validate(flow)
    end

    test "rejects node with missing type/position/data" do
      flow = put_in(@valid_flow["nodes"], [%{"id" => "n1"}])
      assert {:error, "node n1: missing required fields" <> _} = BlackboexFlow.validate(flow)
    end

    test "rejects node with invalid type" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{
            "id" => "n1",
            "type" => "http_request",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{}
          }
        ])

      assert {:error, "node n1: invalid type 'http_request'" <> _} = BlackboexFlow.validate(flow)
    end

    test "rejects node with non-numeric position" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => "bad", "y" => 0},
            "data" => %{}
          }
        ])

      assert {:error, "node n1: position must have numeric x and y"} =
               BlackboexFlow.validate(flow)
    end

    test "rejects duplicate node ids" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{"id" => "n1", "type" => "end", "position" => %{"x" => 100, "y" => 0}, "data" => %{}}
        ])

      assert {:error, "duplicate node ids: n1"} = BlackboexFlow.validate(flow)
    end

    test "rejects missing edges field" do
      flow = Map.delete(@valid_flow, "edges")
      assert {:error, "missing required field: edges"} = BlackboexFlow.validate(flow)
    end

    test "rejects edge without id" do
      flow = put_in(@valid_flow["edges"], [%{"source" => "n1", "target" => "n2"}])
      assert {:error, "edge missing required field: id"} = BlackboexFlow.validate(flow)
    end

    test "rejects edge with missing fields" do
      flow = put_in(@valid_flow["edges"], [%{"id" => "e1", "source" => "n1"}])
      assert {:error, "edge e1: missing or invalid fields" <> _} = BlackboexFlow.validate(flow)
    end

    test "rejects edge referencing non-existent source node" do
      flow =
        put_in(@valid_flow["edges"], [
          %{
            "id" => "e1",
            "source" => "ghost",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          }
        ])

      assert {:error, "edge e1: source 'ghost' references non-existent node"} =
               BlackboexFlow.validate(flow)
    end

    test "rejects edge referencing non-existent target node" do
      flow =
        put_in(@valid_flow["edges"], [
          %{
            "id" => "e1",
            "source" => "n1",
            "source_port" => 0,
            "target" => "ghost",
            "target_port" => 0
          }
        ])

      assert {:error, "edge e1: target 'ghost' references non-existent node"} =
               BlackboexFlow.validate(flow)
    end

    test "rejects non-map input" do
      assert {:error, "definition must be a map"} = BlackboexFlow.validate("not a map")
      assert {:error, "definition must be a map"} = BlackboexFlow.validate(nil)
    end
  end

  describe "current_version/0" do
    test "returns 1.0" do
      assert "1.0" = BlackboexFlow.current_version()
    end
  end
end
