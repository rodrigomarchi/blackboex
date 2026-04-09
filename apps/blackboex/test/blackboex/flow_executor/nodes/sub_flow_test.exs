defmodule Blackboex.FlowExecutor.Nodes.SubFlowTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.FlowExecutor.Nodes.SubFlow
  alias Blackboex.Flows

  # Ensure node type atoms exist for DefinitionParser.safe_to_atom/1
  _ = :sub_flow

  # Minimal flow definition: start → end (passes input through unchanged)
  defp passthrough_definition do
    %{
      "version" => "1.0",
      "nodes" => [
        %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
        %{"id" => "n2", "type" => "end", "position" => %{"x" => 200, "y" => 0}, "data" => %{}}
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
  end

  # Flow definition: start → elixir_code → end, uppercases a string input
  defp upcase_definition do
    %{
      "version" => "1.0",
      "nodes" => [
        %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
        %{
          "id" => "n2",
          "type" => "elixir_code",
          "position" => %{"x" => 200, "y" => 0},
          "data" => %{"code" => "String.upcase(input)"}
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

  setup do
    {user, org} = user_and_org_fixture()
    sub_flow = flow_fixture(%{user: user, org: org, definition: passthrough_definition()})
    %{org: org, sub_flow: sub_flow}
  end

  describe "run/3 — happy path" do
    test "executes sub-flow and returns result wrapped in parent state", %{
      org: org,
      sub_flow: sub_flow
    } do
      args = %{prev_result: %{output: "hello", state: %{}}}
      opts = [flow_id: sub_flow.id, timeout_ms: 5_000]
      context = %{organization_id: org.id}

      assert {:ok, %{output: output, state: state}} = SubFlow.run(args, context, opts)
      assert state["sub_flow_result"] == output
    end

    test "sub-flow output replaces current input in result", %{org: org, sub_flow: sub_flow} do
      {:ok, sub_flow} = Flows.update_definition(sub_flow, upcase_definition())

      args = %{prev_result: %{output: "hello", state: %{}}}
      opts = [flow_id: sub_flow.id, timeout_ms: 5_000]
      context = %{organization_id: org.id}

      assert {:ok, %{output: "HELLO", state: state}} = SubFlow.run(args, context, opts)
      assert state["sub_flow_result"] == "HELLO"
    end

    test "state preservation: parent state is preserved and sub_flow_result added", %{
      org: org,
      sub_flow: sub_flow
    } do
      args = %{prev_result: %{output: "data", state: %{"existing_key" => "preserved"}}}
      opts = [flow_id: sub_flow.id, timeout_ms: 5_000]
      context = %{organization_id: org.id}

      assert {:ok, %{state: state}} = SubFlow.run(args, context, opts)
      assert state["existing_key"] == "preserved"
      assert Map.has_key?(state, "sub_flow_result")
    end

    test "accepts input from first-node shape (no prev_result)", %{
      org: org,
      sub_flow: sub_flow
    } do
      args = %{input: "first_node_input"}
      opts = [flow_id: sub_flow.id, timeout_ms: 5_000]
      context = %{organization_id: org.id}

      assert {:ok, %{output: _, state: state}} = SubFlow.run(args, context, opts)
      assert Map.has_key?(state, "sub_flow_result")
    end
  end

  describe "run/3 — input_mapping" do
    test "with empty input_mapping, current input is passed through", %{
      org: org,
      sub_flow: sub_flow
    } do
      args = %{prev_result: %{output: %{"name" => "alice"}, state: %{}}}
      opts = [flow_id: sub_flow.id, timeout_ms: 5_000, input_mapping: %{}]
      context = %{organization_id: org.id}

      assert {:ok, %{state: state}} = SubFlow.run(args, context, opts)
      assert Map.has_key?(state, "sub_flow_result")
    end

    test "input_mapping expressions are evaluated to build sub-flow payload", %{
      org: org,
      sub_flow: sub_flow
    } do
      # passthrough sub-flow returns whatever payload is passed in
      args = %{prev_result: %{output: %{"name" => "alice"}, state: %{"greeting" => "hi"}}}
      # Build payload as a map using expressions referencing input and state
      opts = [
        flow_id: sub_flow.id,
        timeout_ms: 5_000,
        input_mapping: %{
          "forwarded_name" => ~s(input["name"]),
          "forwarded_greeting" => ~s(state["greeting"])
        }
      ]

      context = %{organization_id: org.id}

      assert {:ok, %{state: state}} = SubFlow.run(args, context, opts)
      # sub_flow_result is the passthrough output: the mapped payload
      assert state["sub_flow_result"]["forwarded_name"] == "alice"
      assert state["sub_flow_result"]["forwarded_greeting"] == "hi"
    end

    test "input_mapping with bad expression returns error", %{org: org, sub_flow: sub_flow} do
      args = %{prev_result: %{output: "data", state: %{}}}

      opts = [
        flow_id: sub_flow.id,
        timeout_ms: 5_000,
        input_mapping: %{"key" => "this is not valid elixir !!@#"}
      ]

      context = %{organization_id: org.id}

      assert {:error, reason} = SubFlow.run(args, context, opts)
      assert reason =~ "input_mapping evaluation failed"
    end
  end

  describe "run/3 — error cases" do
    test "returns error when flow_id references a non-existent flow", %{org: org} do
      args = %{prev_result: %{output: "data", state: %{}}}
      opts = [flow_id: Ecto.UUID.generate(), timeout_ms: 5_000]
      context = %{organization_id: org.id}

      assert {:error, reason} = SubFlow.run(args, context, opts)
      assert reason =~ "sub-flow not found"
    end

    test "returns error when organization_id is absent from context", %{sub_flow: sub_flow} do
      args = %{prev_result: %{output: "data", state: %{}}}
      opts = [flow_id: sub_flow.id, timeout_ms: 5_000]
      context = %{}

      assert {:error, reason} = SubFlow.run(args, context, opts)
      assert reason =~ "organization_id not in context"
    end

    test "returns error when flow belongs to a different org", %{sub_flow: sub_flow} do
      {_user2, org2} = user_and_org_fixture()

      args = %{prev_result: %{output: "data", state: %{}}}
      opts = [flow_id: sub_flow.id, timeout_ms: 5_000]
      context = %{organization_id: org2.id}

      assert {:error, reason} = SubFlow.run(args, context, opts)
      assert reason =~ "sub-flow not found"
    end
  end

  describe "run/3 — depth limit" do
    test "returns error when sub_flow_depth process key reaches max depth", %{
      org: org,
      sub_flow: sub_flow
    } do
      Process.put(:sub_flow_depth, 5)

      args = %{prev_result: %{output: "data", state: %{}}}
      opts = [flow_id: sub_flow.id, timeout_ms: 5_000]
      context = %{organization_id: org.id}

      assert {:error, reason} = SubFlow.run(args, context, opts)
      assert reason =~ "depth limit exceeded"

      Process.delete(:sub_flow_depth)
    end
  end

  describe "run/3 — timeout" do
    test "returns error when sub-flow exceeds timeout_ms", _context do
      # Build a slow sub-flow with a sleep code node
      slow_definition = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"code" => ":timer.sleep(5000); input", "timeout_ms" => 10_000}
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

      {user, org} = user_and_org_fixture()
      slow_flow = flow_fixture(%{user: user, org: org, definition: slow_definition})

      args = %{prev_result: %{output: "data", state: %{}}}
      opts = [flow_id: slow_flow.id, timeout_ms: 100]
      context = %{organization_id: slow_flow.organization_id}

      assert {:error, reason} = SubFlow.run(args, context, opts)
      assert reason =~ "timed out"
    end
  end
end
