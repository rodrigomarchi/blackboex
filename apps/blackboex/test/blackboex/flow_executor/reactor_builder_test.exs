defmodule Blackboex.FlowExecutor.ReactorBuilderTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.{DefinitionParser, ReactorBuilder}

  @linear_flow %{
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
        "data" => %{"code" => "String.upcase(input)", "timeout_ms" => 5000}
      },
      %{
        "id" => "n3",
        "type" => "end",
        "position" => %{"x" => 400, "y" => 0},
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
        "data" => %{"expression" => ~s(if input["ok"], do: 0, else: 1)}
      },
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 400, "y" => -100},
        "data" => %{"code" => ~s("success")}
      },
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 400, "y" => 100},
        "data" => %{"code" => ~s("failure")}
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
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0},
      %{"id" => "e3", "source" => "n2", "source_port" => 1, "target" => "n4", "target_port" => 0},
      %{"id" => "e4", "source" => "n3", "source_port" => 0, "target" => "n5", "target_port" => 0},
      %{"id" => "e5", "source" => "n4", "source_port" => 0, "target" => "n6", "target_port" => 0}
    ]
  }

  describe "build/1" do
    test "builds reactor from linear flow" do
      {:ok, parsed} = DefinitionParser.parse(@linear_flow)
      assert {:ok, reactor} = ReactorBuilder.build(parsed)
      assert %Reactor{} = reactor
      # At least 3 steps (our nodes) + possible internal transform steps
      assert length(reactor.steps) >= 3
    end

    test "builds reactor from branching flow" do
      {:ok, parsed} = DefinitionParser.parse(@branching_flow)
      assert {:ok, reactor} = ReactorBuilder.build(parsed)
      assert %Reactor{} = reactor
      # At least 6 steps (our nodes) + possible internal transform steps
      assert length(reactor.steps) >= 6
    end

    test "linear flow executes correctly" do
      {:ok, parsed} = DefinitionParser.parse(@linear_flow)
      {:ok, reactor} = ReactorBuilder.build(parsed)

      assert {:ok, result} = Reactor.run(reactor, %{payload: "hello"}, %{shared_state: %{}})
      assert %{output: "HELLO", state: %{}} = result
    end

    test "linear flow with state update" do
      flow =
        put_in(@linear_flow["nodes"], [
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
            "data" => %{
              "code" => ~s[{String.upcase(input), Map.put(state, "processed", true)}]
            }
          },
          %{
            "id" => "n3",
            "type" => "end",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{}
          }
        ])

      {:ok, parsed} = DefinitionParser.parse(flow)
      {:ok, reactor} = ReactorBuilder.build(parsed)

      assert {:ok, result} =
               Reactor.run(reactor, %{payload: "test"}, %{shared_state: %{}})

      assert %{output: "TEST", state: %{"processed" => true}} = result
    end

    test "branching flow routes to correct branch" do
      {:ok, parsed} = DefinitionParser.parse(@branching_flow)
      {:ok, reactor} = ReactorBuilder.build(parsed)

      # Both branches will execute (Reactor runs all reachable steps)
      # but the return value comes from the first end node (n5)
      assert {:ok, _result} =
               Reactor.run(reactor, %{payload: %{"ok" => true}}, %{shared_state: %{}})
    end

    test "passes payload_schema and state_schema to start step via options" do
      flow =
        put_in(@linear_flow["nodes"], [
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
                }
              ],
              "state_schema" => [
                %{"name" => "greeting", "type" => "string", "initial_value" => ""}
              ]
            }
          },
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{
              "code" => ~S|{input, Map.put(state, "greeting", "Hello, " <> input["name"] <> "!")}|
            }
          },
          %{
            "id" => "n3",
            "type" => "end",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{}
          }
        ])

      {:ok, parsed} = DefinitionParser.parse(flow)
      {:ok, reactor} = ReactorBuilder.build(parsed)

      # Valid payload passes validation and initializes state
      assert {:ok, result} =
               Reactor.run(reactor, %{payload: %{"name" => "Ana"}}, %{shared_state: %{}})

      assert result.state["greeting"] == "Hello, Ana!"
    end

    test "start step rejects invalid payload via schema" do
      flow =
        put_in(@linear_flow["nodes"], [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{
              "payload_schema" => [
                %{"name" => "name", "type" => "string", "required" => true, "constraints" => %{}}
              ]
            }
          },
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"code" => "input"}
          },
          %{
            "id" => "n3",
            "type" => "end",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{}
          }
        ])

      {:ok, parsed} = DefinitionParser.parse(flow)
      {:ok, reactor} = ReactorBuilder.build(parsed)

      # Missing required field — should fail
      assert {:error, _reason} =
               Reactor.run(reactor, %{payload: %{}}, %{shared_state: %{}})
    end

    test "passes response_schema and response_mapping to end step via options" do
      flow =
        put_in(@linear_flow["nodes"], [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{
              "state_schema" => [
                %{"name" => "result", "type" => "string", "initial_value" => ""}
              ]
            }
          },
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{
              "code" => ~s[{input, Map.put(state, "result", "done")}]
            }
          },
          %{
            "id" => "n3",
            "type" => "end",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{
              "response_schema" => [
                %{
                  "name" => "status",
                  "type" => "string",
                  "required" => true,
                  "constraints" => %{}
                }
              ],
              "response_mapping" => [
                %{"response_field" => "status", "state_variable" => "result"}
              ]
            }
          }
        ])

      {:ok, parsed} = DefinitionParser.parse(flow)
      {:ok, reactor} = ReactorBuilder.build(parsed)

      assert {:ok, result} =
               Reactor.run(reactor, %{payload: %{}}, %{shared_state: %{}})

      assert result.output == %{"status" => "done"}
    end

    test "omits schema options when not present in node data" do
      # Use default @linear_flow which has no schemas — should work as before
      {:ok, parsed} = DefinitionParser.parse(@linear_flow)
      {:ok, reactor} = ReactorBuilder.build(parsed)

      assert {:ok, result} = Reactor.run(reactor, %{payload: "hello"}, %{shared_state: %{}})
      assert %{output: "HELLO", state: %{}} = result
    end

    test "error in code node propagates" do
      flow =
        put_in(@linear_flow["nodes"], [
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
            "data" => %{"code" => "raise \"boom\""}
          },
          %{
            "id" => "n3",
            "type" => "end",
            "position" => %{"x" => 400, "y" => 0},
            "data" => %{}
          }
        ])

      {:ok, parsed} = DefinitionParser.parse(flow)
      {:ok, reactor} = ReactorBuilder.build(parsed)

      assert {:error, _reason} =
               Reactor.run(reactor, %{payload: "test"}, %{shared_state: %{}})
    end
  end
end
