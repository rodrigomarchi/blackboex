defmodule Blackboex.FlowExecutorTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.Flows

  @linear_definition %{
    "version" => "1.0",
    "nodes" => [
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 0, "y" => 0},
        "data" => %{"execution_mode" => "sync", "timeout_ms" => 30_000}
      },
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 200, "y" => 0},
        "data" => %{"code" => ~s|String.upcase(input["name"])|, "timeout_ms" => 5000}
      },
      %{
        "id" => "n3",
        "type" => "end",
        "position" => %{"x" => 400, "y" => 0},
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
      }
    ]
  }

  setup do
    {user, org} = user_and_org_fixture()
    %{user: user, org: org}
  end

  defp create_flow_with_definition(user, org, definition) do
    {:ok, flow} =
      Flows.create_flow(%{
        name: "Test Flow #{System.unique_integer([:positive])}",
        organization_id: org.id,
        user_id: user.id
      })

    {:ok, flow} = Flows.update_definition(flow, definition)
    flow
  end

  describe "run/3" do
    test "executes a linear flow correctly", %{user: user, org: org} do
      flow = create_flow_with_definition(user, org, @linear_definition)

      assert {:ok, result} = FlowExecutor.run(flow, %{"name" => "hello"})
      assert %{output: "HELLO", state: _} = result
    end

    test "returns error for invalid definition", %{user: user, org: org} do
      {:ok, flow} =
        Flows.create_flow(%{
          name: "Bad Flow",
          organization_id: org.id,
          user_id: user.id
        })

      assert {:error, _reason} = FlowExecutor.run(flow, %{"value" => "test"})
    end

    test "returns error when code raises", %{user: user, org: org} do
      definition =
        put_in(@linear_definition["nodes"], [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"code" => ~s|raise "boom"|, "timeout_ms" => 5000}
          },
          %{"id" => "n3", "type" => "end", "position" => %{"x" => 400, "y" => 0}, "data" => %{}}
        ])

      flow = create_flow_with_definition(user, org, definition)
      assert {:error, _reason} = FlowExecutor.run(flow, %{"value" => "test"})
    end
  end

  describe "execute_sync/2" do
    test "creates execution record and returns result", %{user: user, org: org} do
      flow = create_flow_with_definition(user, org, @linear_definition)

      assert {:ok, result} = FlowExecutor.execute_sync(flow, %{"name" => "hello"})
      assert %{output: %{output: "HELLO"}, execution_id: exec_id, duration_ms: dur} = result
      assert is_binary(exec_id)
      assert is_integer(dur)

      # Verify execution record was created and completed
      execution = FlowExecutions.get_execution(exec_id)
      assert execution.status == "completed"
      assert execution.input == %{"name" => "hello"}
    end

    test "creates failed execution on error", %{user: user, org: org} do
      definition =
        put_in(@linear_definition["nodes"], [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"code" => ~s|raise "boom"|}
          },
          %{"id" => "n3", "type" => "end", "position" => %{"x" => 400, "y" => 0}, "data" => %{}}
        ])

      flow = create_flow_with_definition(user, org, definition)

      assert {:error, %{error: error_msg, execution_id: exec_id}} =
               FlowExecutor.execute_sync(flow, %{"name" => "test"})

      assert is_binary(error_msg)

      execution = FlowExecutions.get_execution(exec_id)
      assert execution.status == "failed"
      assert execution.error != nil
    end

    test "state accumulates across nodes", %{user: user, org: org} do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{
              "code" => ~s|{input, Map.put(state, "step1", true)}|
            }
          },
          %{
            "id" => "n3",
            "type" => "elixir_code",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{
              "code" => ~s|{input, Map.put(state, "step2", true)}|
            }
          },
          %{"id" => "n4", "type" => "end", "position" => %{"x" => 600, "y" => 0}, "data" => %{}}
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

      flow = create_flow_with_definition(user, org, definition)

      assert {:ok, result} = FlowExecutor.execute_sync(flow, %{"value" => "data"})
      assert %{output: %{output: %{"value" => "data"}, state: final_state}} = result
      assert final_state["step1"] == true
      assert final_state["step2"] == true
    end
  end

  describe "execute_async/2" do
    test "creates execution and enqueues Oban job", %{user: user, org: org} do
      flow = create_flow_with_definition(user, org, @linear_definition)

      assert {:ok, %{execution_id: exec_id}} =
               FlowExecutor.execute_async(flow, %{"name" => "hello"})

      assert is_binary(exec_id)

      # Execution should be pending (Oban job not executed in test mode)
      execution = FlowExecutions.get_execution(exec_id)
      assert execution.status == "pending"
      assert execution.input == %{"name" => "hello"}
    end
  end
end
