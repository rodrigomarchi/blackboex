defmodule Blackboex.FlowExecutor.Integration.SchemaExecutionTest do
  @moduledoc """
  Integration tests validating the full flow execution pipeline with schemas:
  schema definition → validation → state init → code execution → response mapping.
  """

  use Blackboex.DataCase, async: false

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.Flows

  # Ensure node type atoms exist for DefinitionParser
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

  defp schema_flow_definition do
    %{
      "version" => "1.0",
      "nodes" => [
        %{
          "id" => "n1",
          "type" => "start",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{
            "payload_schema" => [
              %{
                "name" => "name",
                "type" => "string",
                "required" => true,
                "constraints" => %{"min_length" => 1}
              },
              %{
                "name" => "count",
                "type" => "integer",
                "required" => false,
                "constraints" => %{"min" => 0}
              }
            ],
            "state_schema" => [
              %{"name" => "greeting", "type" => "string", "initial_value" => ""},
              %{"name" => "total", "type" => "integer", "initial_value" => 0}
            ]
          }
        },
        %{
          "id" => "n2",
          "type" => "elixir_code",
          "position" => %{"x" => 200, "y" => 0},
          "data" => %{
            "code" => ~S"""
            count = input["count"] || 1
            greeting = "Hello, #{input["name"]}!"
            new_state = %{state | "greeting" => greeting, "total" => count}
            {input, new_state}
            """
          }
        },
        %{
          "id" => "n3",
          "type" => "end",
          "position" => %{"x" => 400, "y" => 0},
          "data" => %{
            "response_schema" => [
              %{
                "name" => "message",
                "type" => "string",
                "required" => true,
                "constraints" => %{}
              },
              %{"name" => "count", "type" => "integer", "required" => true, "constraints" => %{}}
            ],
            "response_mapping" => [
              %{"response_field" => "message", "state_variable" => "greeting"},
              %{"response_field" => "count", "state_variable" => "total"}
            ]
          }
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
  end

  describe "full flow execution with schemas" do
    @tag :integration
    test "executes flow: valid payload → state init → code mutates state → end maps response",
         %{flow: flow} do
      flow = set_definition!(flow, schema_flow_definition())
      input = %{"name" => "Ana", "count" => 5}

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)

      output = result.output
      assert output == %{"message" => "Hello, Ana!", "count" => 5}
    end

    @tag :integration
    test "rejects execution with invalid payload and records failure in FlowExecution",
         %{flow: flow} do
      flow = set_definition!(flow, schema_flow_definition())
      input = %{}

      assert {:error, result} = FlowExecutor.execute_sync(flow, input)
      assert result.error =~ "Payload validation failed"
      assert result.error =~ "name"
    end

    @tag :integration
    test "initializes state variables accessible in elixir_code node", %{flow: flow} do
      flow = set_definition!(flow, schema_flow_definition())
      input = %{"name" => "Test"}

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      # State should have been initialized with schema values and then mutated
      assert execution.shared_state["greeting"] == "Hello, Test!"
      assert execution.shared_state["total"] == 1
    end

    @tag :integration
    test "end node maps mutated state to response with renamed fields", %{flow: flow} do
      flow = set_definition!(flow, schema_flow_definition())
      input = %{"name" => "Maria", "count" => 42}

      assert {:ok, result} = FlowExecutor.execute_sync(flow, input)

      output = result.output
      # "greeting" state var → "message" response field
      assert output["message"] == "Hello, Maria!"
      # "total" state var → "count" response field
      assert output["count"] == 42
    end

    @tag :integration
    test "backward compatible: flow without schemas executes as before", %{flow: flow} do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"code" => ~S|input["value"]|}
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

      flow = set_definition!(flow, definition)
      assert {:ok, result} = FlowExecutor.execute_sync(flow, %{"value" => "hello"})
      output = result.output
      assert output == "hello"
    end

    @tag :integration
    test "flow with empty schemas executes as before", %{flow: flow} do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{"payload_schema" => [], "state_schema" => []}
          },
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"code" => ~S|input["value"]|}
          },
          %{
            "id" => "n3",
            "type" => "end",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{"response_schema" => [], "response_mapping" => []}
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

      flow = set_definition!(flow, definition)
      assert {:ok, result} = FlowExecutor.execute_sync(flow, %{"value" => "hello"})
      output = result.output
      assert output == "hello"
    end

    @tag :integration
    test "execution failure from payload validation sets FlowExecution.status to 'failed'",
         %{flow: flow} do
      flow = set_definition!(flow, schema_flow_definition())
      input = %{"name" => "", "count" => -1}

      assert {:error, result} = FlowExecutor.execute_sync(flow, input)

      execution = FlowExecutions.get_execution(result.execution_id)
      assert execution.status == "failed"
      assert execution.error =~ "Payload validation failed"
    end

    @tag :integration
    test "payload validation error includes descriptive field-level messages",
         %{flow: flow} do
      flow = set_definition!(flow, schema_flow_definition())
      input = %{"count" => -5}

      assert {:error, result} = FlowExecutor.execute_sync(flow, input)
      assert result.error =~ "name"
      assert result.error =~ "required"
    end

    @tag :integration
    test "string constraint min_length enforced at execution", %{flow: flow} do
      flow = set_definition!(flow, schema_flow_definition())
      input = %{"name" => ""}

      assert {:error, result} = FlowExecutor.execute_sync(flow, input)
      assert result.error =~ "name"
    end

    @tag :integration
    test "integer constraint min enforced at execution", %{flow: flow} do
      flow = set_definition!(flow, schema_flow_definition())
      input = %{"name" => "Ok", "count" => -1}

      assert {:error, result} = FlowExecutor.execute_sync(flow, input)
      assert result.error =~ "count"
      assert result.error =~ ">="
    end
  end
end
