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
            "type" => "unknown_type",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{}
          }
        ])

      assert {:error, "node n1: invalid type 'unknown_type'" <> _} = BlackboexFlow.validate(flow)
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

  describe "validate/1 — schema fields in node data" do
    test "accepts start node with valid payload_schema" do
      flow =
        put_in(@valid_flow["nodes"], [
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
          %{"id" => "n2", "type" => "end", "position" => %{"x" => 100, "y" => 0}, "data" => %{}}
        ])

      flow = %{flow | "edges" => []}
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts start node with valid state_schema" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{
              "state_schema" => [
                %{
                  "name" => "counter",
                  "type" => "integer",
                  "required" => true,
                  "constraints" => %{},
                  "initial_value" => 0
                }
              ]
            }
          },
          %{"id" => "n2", "type" => "end", "position" => %{"x" => 100, "y" => 0}, "data" => %{}}
        ])

      flow = %{flow | "edges" => []}
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts start node with both payload_schema and state_schema" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{
              "payload_schema" => [
                %{"name" => "name", "type" => "string", "required" => true, "constraints" => %{}}
              ],
              "state_schema" => [
                %{
                  "name" => "count",
                  "type" => "integer",
                  "required" => false,
                  "constraints" => %{},
                  "initial_value" => 0
                }
              ]
            }
          },
          %{"id" => "n2", "type" => "end", "position" => %{"x" => 100, "y" => 0}, "data" => %{}}
        ])

      flow = %{flow | "edges" => []}
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts start node without any schema (backward compatible)" do
      assert :ok = BlackboexFlow.validate(@valid_flow)
    end

    test "rejects start node with malformed payload_schema" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{
              "payload_schema" => [
                %{
                  "name" => "x",
                  "type" => "invalid_type",
                  "required" => true,
                  "constraints" => %{}
                }
              ]
            }
          },
          %{"id" => "n2", "type" => "end", "position" => %{"x" => 100, "y" => 0}, "data" => %{}}
        ])

      flow = %{flow | "edges" => []}
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "payload_schema"
    end

    test "rejects start node with malformed state_schema" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{
              "state_schema" => [
                %{"name" => "", "type" => "string", "required" => false, "constraints" => %{}}
              ]
            }
          },
          %{"id" => "n2", "type" => "end", "position" => %{"x" => 100, "y" => 0}, "data" => %{}}
        ])

      flow = %{flow | "edges" => []}
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "state_schema"
    end

    test "accepts end node with valid response_schema and response_mapping" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "end",
            "position" => %{"x" => 100, "y" => 0},
            "data" => %{
              "response_schema" => [
                %{
                  "name" => "total",
                  "type" => "integer",
                  "required" => true,
                  "constraints" => %{}
                }
              ],
              "response_mapping" => [
                %{"response_field" => "total", "state_variable" => "counter"}
              ]
            }
          }
        ])

      flow = %{flow | "edges" => []}
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts end node without response_schema (backward compatible)" do
      assert :ok = BlackboexFlow.validate(@valid_flow)
    end

    test "rejects end node with response_mapping referencing non-existent response field" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "end",
            "position" => %{"x" => 100, "y" => 0},
            "data" => %{
              "response_schema" => [
                %{
                  "name" => "total",
                  "type" => "integer",
                  "required" => true,
                  "constraints" => %{}
                }
              ],
              "response_mapping" => [
                %{"response_field" => "nonexistent", "state_variable" => "counter"}
              ]
            }
          }
        ])

      flow = %{flow | "edges" => []}
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "nonexistent"
    end

    test "rejects end node with duplicate response_field in mapping" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "end",
            "position" => %{"x" => 100, "y" => 0},
            "data" => %{
              "response_schema" => [
                %{
                  "name" => "total",
                  "type" => "integer",
                  "required" => true,
                  "constraints" => %{}
                }
              ],
              "response_mapping" => [
                %{"response_field" => "total", "state_variable" => "a"},
                %{"response_field" => "total", "state_variable" => "b"}
              ]
            }
          }
        ])

      flow = %{flow | "edges" => []}
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "duplicate"
    end

    test "rejects end node with response_mapping but no response_schema" do
      flow =
        put_in(@valid_flow["nodes"], [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "end",
            "position" => %{"x" => 100, "y" => 0},
            "data" => %{
              "response_mapping" => [
                %{"response_field" => "total", "state_variable" => "counter"}
              ]
            }
          }
        ])

      flow = %{flow | "edges" => []}
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "response_schema"
    end

    test "full flow with start schemas + end mapping validates successfully" do
      flow =
        put_in(@valid_flow["nodes"], [
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
                %{
                  "name" => "greeting",
                  "type" => "string",
                  "required" => false,
                  "constraints" => %{},
                  "initial_value" => ""
                }
              ]
            }
          },
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 200, "y" => 0},
            "data" => %{"name" => "Greet", "code" => "{input, state}"}
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
                }
              ],
              "response_mapping" => [
                %{"response_field" => "message", "state_variable" => "greeting"}
              ]
            }
          }
        ])

      assert :ok = BlackboexFlow.validate(flow)
    end
  end

  describe "current_version/0" do
    test "returns 1.0" do
      assert "1.0" = BlackboexFlow.current_version()
    end
  end

  describe "validate/1 — http_request node" do
    defp http_request_flow(data) do
      %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "http_request",
            "position" => %{"x" => 200, "y" => 0},
            "data" => data
          },
          %{"id" => "n3", "type" => "end", "position" => %{"x" => 400, "y" => 0}, "data" => %{}}
        ],
        "edges" => []
      }
    end

    test "accepts valid http_request node with required fields" do
      flow = http_request_flow(%{"method" => "GET", "url" => "https://example.com"})
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts valid http_request node with all optional fields" do
      data = %{
        "method" => "POST",
        "url" => "https://api.example.com/data",
        "headers" => %{"Authorization" => "Bearer token"},
        "body_template" => "{\"key\": \"value\"}",
        "timeout_ms" => 5000,
        "max_retries" => 3,
        "auth_type" => "bearer",
        "auth_config" => %{"token" => "my_token"},
        "expected_status" => [200, 201]
      }

      flow = http_request_flow(data)
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts all valid HTTP methods" do
      for method <- ~w(GET POST PUT PATCH DELETE) do
        flow = http_request_flow(%{"method" => method, "url" => "https://example.com"})
        assert :ok = BlackboexFlow.validate(flow), "expected :ok for method #{method}"
      end
    end

    test "rejects http_request with missing url" do
      flow = http_request_flow(%{"method" => "GET"})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "url"
    end

    test "rejects http_request with missing method" do
      flow = http_request_flow(%{"url" => "https://example.com"})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "method"
    end

    test "rejects http_request with invalid method" do
      flow = http_request_flow(%{"method" => "INVALID", "url" => "https://example.com"})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "method"
    end

    test "rejects http_request with empty url" do
      flow = http_request_flow(%{"method" => "GET", "url" => ""})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "url"
    end

    test "rejects http_request with non-map headers" do
      flow =
        http_request_flow(%{
          "method" => "GET",
          "url" => "https://example.com",
          "headers" => "bad"
        })

      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "headers"
    end

    test "rejects http_request with negative timeout_ms" do
      flow =
        http_request_flow(%{
          "method" => "GET",
          "url" => "https://example.com",
          "timeout_ms" => -1
        })

      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "timeout_ms"
    end

    test "rejects http_request with invalid auth_type" do
      flow =
        http_request_flow(%{
          "method" => "GET",
          "url" => "https://example.com",
          "auth_type" => "oauth"
        })

      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "auth_type"
    end

    test "rejects http_request with non-integer in expected_status" do
      flow =
        http_request_flow(%{
          "method" => "GET",
          "url" => "https://example.com",
          "expected_status" => [200, "ok"]
        })

      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "expected_status"
    end
  end

  describe "validate/1 — delay node" do
    defp delay_flow(data) do
      %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "delay",
            "position" => %{"x" => 200, "y" => 0},
            "data" => data
          },
          %{"id" => "n3", "type" => "end", "position" => %{"x" => 400, "y" => 0}, "data" => %{}}
        ],
        "edges" => []
      }
    end

    test "accepts valid delay node with required duration_ms" do
      flow = delay_flow(%{"duration_ms" => 1000})
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts valid delay node with optional max_duration_ms" do
      flow = delay_flow(%{"duration_ms" => 1000, "max_duration_ms" => 5000})
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "rejects delay with missing duration_ms" do
      flow = delay_flow(%{})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "duration_ms"
    end

    test "rejects delay with zero duration_ms" do
      flow = delay_flow(%{"duration_ms" => 0})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "duration_ms"
    end

    test "rejects delay with negative duration_ms" do
      flow = delay_flow(%{"duration_ms" => -500})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "duration_ms"
    end

    test "rejects delay with non-integer duration_ms" do
      flow = delay_flow(%{"duration_ms" => "1000"})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "duration_ms"
    end
  end

  describe "validate/1 — for_each node" do
    defp for_each_flow(data) do
      %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "for_each",
            "position" => %{"x" => 200, "y" => 0},
            "data" => data
          },
          %{"id" => "n3", "type" => "end", "position" => %{"x" => 400, "y" => 0}, "data" => %{}}
        ],
        "edges" => []
      }
    end

    test "accepts valid for_each node with required fields" do
      flow = for_each_flow(%{"source_expression" => "state.items", "body_code" => "item * 2"})
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts valid for_each node with all optional fields" do
      data = %{
        "source_expression" => "state.items",
        "body_code" => "item * 2",
        "item_variable" => "item",
        "accumulator" => "results",
        "batch_size" => 10,
        "timeout_ms" => 30_000
      }

      flow = for_each_flow(data)
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "rejects for_each with missing source_expression" do
      flow = for_each_flow(%{"body_code" => "item * 2"})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "source_expression"
    end

    test "rejects for_each with missing body_code" do
      flow = for_each_flow(%{"source_expression" => "state.items"})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "body_code"
    end

    test "rejects for_each with empty source_expression" do
      flow = for_each_flow(%{"source_expression" => "", "body_code" => "item * 2"})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "source_expression"
    end

    test "rejects for_each with empty body_code" do
      flow = for_each_flow(%{"source_expression" => "state.items", "body_code" => ""})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "body_code"
    end

    test "rejects for_each with invalid item_variable (contains spaces)" do
      flow =
        for_each_flow(%{
          "source_expression" => "state.items",
          "body_code" => "item * 2",
          "item_variable" => "my item"
        })

      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "item_variable"
    end

    test "rejects for_each with batch_size out of range" do
      flow =
        for_each_flow(%{
          "source_expression" => "state.items",
          "body_code" => "item * 2",
          "batch_size" => 0
        })

      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "batch_size"
    end

    test "rejects for_each with batch_size over 100" do
      flow =
        for_each_flow(%{
          "source_expression" => "state.items",
          "body_code" => "item * 2",
          "batch_size" => 101
        })

      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "batch_size"
    end
  end

  describe "validate/1 — webhook_wait node" do
    defp webhook_wait_flow(data) do
      %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "webhook_wait",
            "position" => %{"x" => 200, "y" => 0},
            "data" => data
          },
          %{"id" => "n3", "type" => "end", "position" => %{"x" => 400, "y" => 0}, "data" => %{}}
        ],
        "edges" => []
      }
    end

    test "accepts valid webhook_wait node with required event_type" do
      flow = webhook_wait_flow(%{"event_type" => "payment.confirmed"})
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts valid webhook_wait node with all optional fields" do
      data = %{
        "event_type" => "payment.confirmed",
        "timeout_ms" => 60_000,
        "resume_path" => "/webhooks/resume"
      }

      flow = webhook_wait_flow(data)
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "rejects webhook_wait with missing event_type" do
      flow = webhook_wait_flow(%{})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "event_type"
    end

    test "rejects webhook_wait with empty event_type" do
      flow = webhook_wait_flow(%{"event_type" => ""})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "event_type"
    end

    test "rejects webhook_wait with non-positive timeout_ms" do
      flow = webhook_wait_flow(%{"event_type" => "payment.confirmed", "timeout_ms" => 0})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "timeout_ms"
    end
  end

  describe "validate/1 — sub_flow node" do
    defp sub_flow_flow(data) do
      %{
        "version" => "1.0",
        "nodes" => [
          %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}},
          %{
            "id" => "n2",
            "type" => "sub_flow",
            "position" => %{"x" => 200, "y" => 0},
            "data" => data
          },
          %{"id" => "n3", "type" => "end", "position" => %{"x" => 400, "y" => 0}, "data" => %{}}
        ],
        "edges" => []
      }
    end

    test "accepts valid sub_flow node with required flow_id" do
      flow = sub_flow_flow(%{"flow_id" => "abc-123-def"})
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts sub_flow with all optional fields" do
      data = %{
        "flow_id" => "abc-123-def",
        "input_mapping" => %{"key" => "state[\"val\"]"},
        "timeout_ms" => 15_000
      }

      flow = sub_flow_flow(data)
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts sub_flow with missing flow_id (draft state)" do
      flow = sub_flow_flow(%{})
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "accepts sub_flow with empty flow_id (draft state)" do
      flow = sub_flow_flow(%{"flow_id" => ""})
      assert :ok = BlackboexFlow.validate(flow)
    end

    test "rejects sub_flow with non-string flow_id" do
      flow = sub_flow_flow(%{"flow_id" => 42})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "flow_id"
    end

    test "rejects sub_flow with non-map input_mapping" do
      flow = sub_flow_flow(%{"flow_id" => "abc", "input_mapping" => "bad"})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "input_mapping"
    end

    test "rejects sub_flow with non-positive timeout_ms" do
      flow = sub_flow_flow(%{"flow_id" => "abc", "timeout_ms" => 0})
      assert {:error, msg} = BlackboexFlow.validate(flow)
      assert msg =~ "timeout_ms"
    end
  end
end
