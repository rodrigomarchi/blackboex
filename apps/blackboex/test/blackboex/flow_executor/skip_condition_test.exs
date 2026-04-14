defmodule Blackboex.FlowExecutor.SkipConditionTest do
  @moduledoc "Tests skip_condition on nodes — skips execution when expression is true."
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor
  alias Blackboex.FlowExecutor.BlackboexFlow
  alias Blackboex.Flows

  # Ensure node type atoms exist for DefinitionParser.safe_to_atom/1
  _ = :elixir_code
  _ = :condition

  # Helper to build a simple flow: start → elixir_code(with skip_condition) → end
  defp build_flow_with_skip(code, skip_condition) do
    %{
      "version" => "1.0",
      "nodes" => [
        %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
        %{
          "id" => "n2",
          "type" => "elixir_code",
          "position" => %{"x" => 200, "y" => 0},
          "data" => %{"code" => code, "skip_condition" => skip_condition}
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
    %{user: user, org: org}
  end

  describe "skip_condition skips node when true" do
    test "node is skipped, input passes through", %{user: user, org: org} do
      definition =
        build_flow_with_skip(
          ~s|String.upcase(input["name"])|,
          ~s|input["skip"] == true|
        )

      {:ok, flow} =
        Flows.create_flow(%{
          name: "Skip Test",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id,
          definition: definition
        })

      # skip=true → code node should be skipped, input passes through
      assert {:ok, result} = FlowExecutor.run(flow, %{"name" => "test", "skip" => true})
      # The output should be the raw input (not upcased), since the node was skipped
      output = extract_output(result)
      refute output == "TEST"
    end

    test "node executes normally when skip_condition is false", %{user: user, org: org} do
      definition =
        build_flow_with_skip(
          ~s|String.upcase(input["name"])|,
          ~s|input["skip"] == true|
        )

      {:ok, flow} =
        Flows.create_flow(%{
          name: "No Skip Test",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id,
          definition: definition
        })

      # skip=false → code node executes normally
      assert {:ok, result} = FlowExecutor.run(flow, %{"name" => "test", "skip" => false})
      output = extract_output(result)
      assert output == "TEST"
    end
  end

  describe "skip_condition absent" do
    test "node executes normally when no skip_condition", %{user: user, org: org} do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"code" => ~s|String.upcase(input["name"])|}
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

      {:ok, flow} =
        Flows.create_flow(%{
          name: "No Skip Condition",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id,
          definition: definition
        })

      assert {:ok, result} = FlowExecutor.run(flow, %{"name" => "test"})
      output = extract_output(result)
      assert output == "TEST"
    end
  end

  describe "BlackboexFlow validation" do
    test "accepts valid skip_condition string" do
      definition = build_flow_with_skip(~s|input|, ~s|true|)
      assert :ok = BlackboexFlow.validate(definition)
    end

    test "rejects non-string skip_condition" do
      definition = build_flow_with_skip(~s|input|, 123)
      assert {:error, msg} = BlackboexFlow.validate(definition)
      assert msg =~ "skip_condition"
    end
  end

  describe "undo/4 delegation" do
    test "delegates undo to inner impl" do
      alias Blackboex.FlowExecutor.Nodes.SkipCondition

      value = %{output: "result", state: %{}}
      args = %{prev_result: %{output: "input", state: %{}}}

      opts = [
        impl: Blackboex.FlowExecutor.Nodes.ElixirCode,
        impl_options: [undo_code: ~s|{input, state}|, timeout_ms: 5_000],
        skip_expression: "false"
      ]

      assert :ok = SkipCondition.undo(value, args, %{}, opts)
    end

    test "returns :ok when impl has no undo" do
      alias Blackboex.FlowExecutor.Nodes.SkipCondition

      value = %{output: "result", state: %{}}
      args = %{prev_result: %{output: "input", state: %{}}}

      opts = [
        impl: Blackboex.FlowExecutor.Nodes.Start,
        impl_options: [],
        skip_expression: "false"
      ]

      assert :ok = SkipCondition.undo(value, args, %{}, opts)
    end
  end

  defp extract_output(%{output: output}), do: output
  defp extract_output(result) when is_map(result), do: result
end
