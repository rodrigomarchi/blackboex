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
      assert result.output == "RODRIGO"

      # Verify FlowExecution in DB
      exec = FlowExecutions.get_execution(result.execution_id)
      assert exec.status == "completed"
      assert exec.duration_ms > 0
      assert exec.input == %{"name" => "rodrigo"}
      # Non-map outputs are wrapped as %{"value" => output} for DB storage
      assert exec.output == %{"value" => "RODRIGO"}

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

      # State is persisted in the FlowExecution shared_state
      exec = FlowExecutions.get_execution(result.execution_id)
      assert exec.shared_state["s1"] == true
      assert exec.shared_state["s2"] == true
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
      assert result.output == "positive"

      exec = FlowExecutions.get_execution(result.execution_id)
      assert exec.status == "completed"
      # Both branches execute (Reactor runs all reachable steps), so we get 6 node executions
      assert length(exec.node_executions) == 6
    end

    test "condition downstream of a skipped condition branch propagates the skip",
         %{flow: flow} do
      # Topology:
      #   n1 start → n2 condition (outer)
      #     branch 0 → n3 elixir_code → n4 condition (inner) → branch 0 → n5 end
      #                                                     → branch 1 → n6 end
      #     branch 1 → n7 elixir_code → n8 end  (first end = Reactor return)
      #
      # We feed input that takes the OUTER branch 1 (→ "outer-1"). The inner
      # condition (n4) still runs because Reactor walks every reachable step,
      # but it receives :__branch_skipped__ as input. Before the fix this
      # crashed with "no function clause matching in Access.get/3". The fix
      # makes the Condition step return a sentinel branch that no source_port
      # can match, so both n5 and n6 propagate the skip and only n8 produces
      # the final result.
      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "condition",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"expression" => ~s|if input["go_inner"] == true, do: 0, else: 1|}
          },
          %{
            "id" => "n3",
            "type" => "elixir_code",
            "position" => %{"x" => 400, "y" => -100},
            "data" => %{"code" => ~s|%{"decision" => "approved"}|}
          },
          %{
            "id" => "n4",
            "type" => "condition",
            "position" => %{"x" => 600, "y" => -100},
            "data" => %{"expression" => ~s|if input["decision"] == "approved", do: 0, else: 1|}
          },
          %{
            "id" => "n5",
            "type" => "end",
            "position" => %{"x" => 800, "y" => -150},
            "data" => %{}
          },
          %{
            "id" => "n6",
            "type" => "end",
            "position" => %{"x" => 800, "y" => -50},
            "data" => %{}
          },
          %{
            "id" => "n7",
            "type" => "elixir_code",
            "position" => %{"x" => 400, "y" => 100},
            "data" => %{"code" => ~s|"outer-1"|}
          },
          %{"id" => "n8", "type" => "end", "position" => %{"x" => 600, "y" => 100}, "data" => %{}}
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
          },
          %{
            "id" => "e4",
            "source" => "n4",
            "source_port" => 0,
            "target" => "n5",
            "target_port" => 0
          },
          %{
            "id" => "e5",
            "source" => "n4",
            "source_port" => 1,
            "target" => "n6",
            "target_port" => 0
          },
          %{
            "id" => "e6",
            "source" => "n2",
            "source_port" => 1,
            "target" => "n7",
            "target_port" => 0
          },
          %{
            "id" => "e7",
            "source" => "n7",
            "source_port" => 0,
            "target" => "n8",
            "target_port" => 0
          }
        ]
      }

      flow = set_definition!(flow, definition)

      # Outer condition takes branch 1 → n7 → n8. The inner condition (n4)
      # runs with a skipped input and must NOT crash.
      assert {:ok, result} = FlowExecutor.execute_sync(flow, %{"go_inner" => false})
      assert result.output == "outer-1"

      exec = FlowExecutions.get_execution(result.execution_id)
      assert exec.status == "completed"

      # Every node runs — including n4 (inner condition) in skipped mode.
      n4_exec = Enum.find(exec.node_executions, &(&1.node_id == "n4"))
      assert n4_exec, "inner condition must produce a NodeExecution record"
      assert n4_exec.status == "completed"
      refute n4_exec.error, "inner condition must not error on skipped input"
    end

    test "condition taking inner branch 0 still routes correctly", %{flow: flow} do
      # Same topology as the previous test, but feed input that takes
      # OUTER branch 0 and then INNER branch 0 (→ n5). Sanity check that
      # the skip-propagation fix did not break the normal routing path.
      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "condition",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"expression" => ~s|if input["go_inner"] == true, do: 0, else: 1|}
          },
          %{
            "id" => "n3",
            "type" => "elixir_code",
            "position" => %{"x" => 400, "y" => -100},
            "data" => %{"code" => ~s|%{"decision" => "approved"}|}
          },
          %{
            "id" => "n4",
            "type" => "condition",
            "position" => %{"x" => 600, "y" => -100},
            "data" => %{"expression" => ~s|if input["decision"] == "approved", do: 0, else: 1|}
          },
          %{
            "id" => "n5",
            "type" => "elixir_code",
            "position" => %{"x" => 800, "y" => -150},
            "data" => %{"code" => ~s|"inner-approved"|}
          },
          %{
            "id" => "n6",
            "type" => "end",
            "position" => %{"x" => 1000, "y" => -150},
            "data" => %{}
          },
          %{
            "id" => "n7",
            "type" => "end",
            "position" => %{"x" => 800, "y" => -50},
            "data" => %{}
          },
          %{
            "id" => "n8",
            "type" => "elixir_code",
            "position" => %{"x" => 400, "y" => 100},
            "data" => %{"code" => ~s|"outer-1"|}
          },
          %{"id" => "n9", "type" => "end", "position" => %{"x" => 600, "y" => 100}, "data" => %{}}
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
          },
          %{
            "id" => "e4",
            "source" => "n4",
            "source_port" => 0,
            "target" => "n5",
            "target_port" => 0
          },
          %{
            "id" => "e5",
            "source" => "n5",
            "source_port" => 0,
            "target" => "n6",
            "target_port" => 0
          },
          %{
            "id" => "e6",
            "source" => "n4",
            "source_port" => 1,
            "target" => "n7",
            "target_port" => 0
          },
          %{
            "id" => "e7",
            "source" => "n2",
            "source_port" => 1,
            "target" => "n8",
            "target_port" => 0
          },
          %{
            "id" => "e8",
            "source" => "n8",
            "source_port" => 0,
            "target" => "n9",
            "target_port" => 0
          }
        ]
      }

      flow = set_definition!(flow, definition)

      assert {:ok, result} = FlowExecutor.execute_sync(flow, %{"go_inner" => true})
      assert result.output == "inner-approved"
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

      assert result.output == %{}

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
