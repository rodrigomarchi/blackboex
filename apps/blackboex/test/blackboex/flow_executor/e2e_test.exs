defmodule Blackboex.FlowExecutor.E2eTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.Flows

  # Ensure node type atoms exist for DefinitionParser.safe_to_atom/1
  _ = :elixir_code
  _ = :condition

  setup do
    {user, org} = user_and_org_fixture()
    flow = flow_fixture(%{user: user, org: org})
    %{user: user, org: org, flow: flow}
  end

  defp set_definition!(flow, definition) do
    {:ok, flow} = Flows.update_definition(flow, definition)
    flow
  end

  defp linear_definition(code) do
    %{
      "version" => "1.0",
      "nodes" => [
        %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
        %{
          "id" => "n2",
          "type" => "elixir_code",
          "position" => %{"x" => 200, "y" => 0},
          "data" => %{"code" => code}
        },
        %{"id" => "n3", "type" => "end", "position" => %{"x" => 400, "y" => 0}, "data" => %{}}
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
  end

  describe "linear flow e2e" do
    test "Start -> ElixirCode(upcase name) -> End", %{flow: flow} do
      code = ~s|String.upcase(input["name"])|
      flow = set_definition!(flow, linear_definition(code))

      assert {:ok, result} = FlowExecutor.execute_sync(flow, %{"name" => "rodrigo"})

      assert result.execution_id
      assert result.duration_ms >= 0
      assert result.output.output == "RODRIGO"

      # Verify FlowExecution in DB
      exec = FlowExecutions.get_execution(result.execution_id)
      assert exec.status == "completed"
      assert exec.duration_ms > 0
      assert exec.input == %{"name" => "rodrigo"}
      # DB output is JSON-serialized (string keys)
      assert exec.output["output"] == "RODRIGO"

      # Verify NodeExecution records (start, elixir_code, end)
      assert length(exec.node_executions) == 3
      assert Enum.all?(exec.node_executions, &(&1.status == "completed"))
    end

    test "state accumulates across multiple code nodes", %{flow: flow} do
      definition = %{
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
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"code" => ~s|{input, Map.put(state, "s1", true)}|}
          },
          %{
            "id" => "n3",
            "type" => "elixir_code",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{"code" => ~s|{input, Map.put(state, "s2", true)}|}
          },
          %{
            "id" => "n4",
            "type" => "end",
            "position" => %{"x" => 600, "y" => 0},
            "data" => %{}
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
          },
          %{
            "id" => "e3",
            "source" => "n3",
            "source_port" => 0,
            "target" => "n4",
            "target_port" => 0
          }
        ]
      }

      flow = set_definition!(flow, definition)
      assert {:ok, result} = FlowExecutor.execute_sync(flow, %{"hello" => "world"})

      assert result.output.state["s1"] == true
      assert result.output.state["s2"] == true
    end

    test "error in code node creates failed execution", %{flow: flow} do
      code = ~s|raise "boom"|
      flow = set_definition!(flow, linear_definition(code))

      assert {:error, result} = FlowExecutor.execute_sync(flow, %{})

      assert result.execution_id
      assert result.error =~ "boom"

      # Verify FlowExecution in DB
      exec = FlowExecutions.get_execution(result.execution_id)
      assert exec.status == "failed"
      assert exec.error =~ "boom"
    end
  end

  describe "branching flow e2e" do
    test "condition routes to correct branch", %{flow: flow} do
      # Condition: if input["x"] > 0, branch 0 (positive), else branch 1 (negative)
      # Branch 0 feeds into the FIRST end node (n5) which is the Reactor return.
      definition = %{
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
            "data" => %{
              "expression" => ~s|if input["x"] > 0, do: 0, else: 1|
            }
          },
          %{
            "id" => "n3",
            "type" => "elixir_code",
            "position" => %{"x" => 400, "y" => -100},
            "data" => %{"code" => ~s|"positive"|}
          },
          %{
            "id" => "n4",
            "type" => "elixir_code",
            "position" => %{"x" => 400, "y" => 100},
            "data" => %{"code" => ~s|"negative"|}
          },
          %{
            "id" => "n5",
            "type" => "end",
            "position" => %{"x" => 600, "y" => -100},
            "data" => %{}
          },
          %{
            "id" => "n6",
            "type" => "end",
            "position" => %{"x" => 600, "y" => 100},
            "data" => %{}
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
          # Branch 0 (positive): condition port 0 -> n3 -> n5 (first end = return)
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
            "target" => "n5",
            "target_port" => 0
          },
          # Branch 1 (negative): condition port 1 -> n4 -> n6
          %{
            "id" => "e4",
            "source" => "n2",
            "source_port" => 1,
            "target" => "n4",
            "target_port" => 0
          },
          %{
            "id" => "e5",
            "source" => "n4",
            "source_port" => 0,
            "target" => "n6",
            "target_port" => 0
          }
        ]
      }

      flow = set_definition!(flow, definition)
      assert {:ok, result} = FlowExecutor.execute_sync(flow, %{"x" => 5})

      # The return is from n5 (first end node). Branch 0 was taken, so output is "positive".
      assert result.output.output == "positive"

      exec = FlowExecutions.get_execution(result.execution_id)
      assert exec.status == "completed"
      # Both branches execute (Reactor runs all reachable steps), so we get 6 node executions
      assert length(exec.node_executions) == 6
    end
  end

  describe "empty/edge cases" do
    test "minimal flow: start -> end with empty input", %{flow: flow} do
      definition = %{
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
            "type" => "end",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{}
          }
        ],
        "edges" => [
          %{
            "id" => "e1",
            "source" => "n1",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          }
        ]
      }

      flow = set_definition!(flow, definition)
      assert {:ok, result} = FlowExecutor.execute_sync(flow, %{})

      assert result.output.output == %{}
      assert result.output.state == %{}

      exec = FlowExecutions.get_execution(result.execution_id)
      assert exec.status == "completed"
      assert length(exec.node_executions) == 2
    end

    test "flow with nil definition returns error", %{flow: flow} do
      # flow_fixture creates a flow without definition (nil by default)
      assert {:error, _} = FlowExecutor.execute_sync(flow, %{})
    end

    test "flow with empty definition returns error", %{flow: flow} do
      flow = set_definition!(flow, %{})
      assert {:error, _} = FlowExecutor.execute_sync(flow, %{})
    end
  end
end
