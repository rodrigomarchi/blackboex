defmodule Blackboex.Samples.FlowTemplates.AllNodesDemo do
  @moduledoc """
  All Nodes Demo template.

  A 10-node flow that exercises all 9 node types available in the flow executor:
  start, elixir_code, condition, end, http_request, delay, sub_flow, for_each, webhook_wait.

  ## Flow graph

      n1: Start (name, email, items, needs_approval)
        → n2: Prepare Greeting (elixir_code)
        → n3: Needs Approval? (condition)

      Branch 0 — Needs Approval:
        → n4: Wait for Approval (webhook_wait)
        → n5: Process Items (for_each)
        → n6: End (approved)

      Branch 1 — Auto Approve:
        → n7: Fetch External Data (http_request)
        → n8: Brief Delay (delay)
        → n9: Send Notification (sub_flow)
        → n10: End (auto-approved)
  """

  @doc "Returns the All Nodes Demo flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "all_nodes_demo",
      name: "All Nodes Demo",
      description:
        "A 10-node flow exercising all 9 node types: start, elixir_code, condition, end, http_request, delay, sub_flow, for_each, webhook_wait",
      category: "Getting Started",
      icon: "hero-squares-2x2",
      definition: definition()
    }
  end

  @doc "Returns the raw BlackboexFlow definition map."
  @spec definition() :: map()
  def definition do
    %{
      "version" => "1.0",
      "nodes" => nodes(),
      "edges" => edges()
    }
  end

  defp nodes do
    [
      # ── n1: Start ──
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 50, "y" => 350},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 60_000,
          "payload_schema" => [
            %{
              "name" => "name",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "email",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "items",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "string"}
            },
            %{
              "name" => "needs_approval",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "greeting",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "processed_items",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "string"},
              "initial_value" => []
            },
            %{
              "name" => "approval_status",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "pending"
            }
          ]
        }
      },

      # ── n2: Prepare Greeting (elixir_code) ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 280, "y" => 350},
        "data" => %{
          "name" => "Prepare Greeting",
          "code" => ~S"""
          greeting = "Hello, #{input["name"]}!"
          new_state = state
            |> Map.put("greeting", greeting)
            |> Map.put("items", input["items"] || [])
          {input, new_state}
          """
        }
      },

      # ── n3: Condition — Needs Approval? ──
      %{
        "id" => "n3",
        "type" => "condition",
        "position" => %{"x" => 510, "y" => 350},
        "data" => %{
          "name" => "Needs Approval?",
          "expression" => ~S"""
          if input["needs_approval"] == true, do: 0, else: 1
          """,
          "branch_labels" => %{
            "0" => "Needs Approval",
            "1" => "Auto Approve"
          }
        }
      },

      # ── n4: Wait for Approval (webhook_wait) — Branch 0 ──
      %{
        "id" => "n4",
        "type" => "webhook_wait",
        "position" => %{"x" => 780, "y" => 150},
        "data" => %{
          "name" => "Wait for Approval",
          "event_type" => "approval",
          "timeout_ms" => 3_600_000
        }
      },

      # ── n5: Process Items (for_each) — Branch 0 ──
      %{
        "id" => "n5",
        "type" => "for_each",
        "position" => %{"x" => 1010, "y" => 150},
        "data" => %{
          "name" => "Process Items",
          "source_expression" => "Map.get(state, \"items\", input[\"items\"] || [])",
          "body_code" => "String.upcase(item)",
          "item_variable" => "item",
          "accumulator" => "processed_items"
        }
      },

      # ── n6: End (Approved) — Branch 0 ──
      %{
        "id" => "n6",
        "type" => "end",
        "position" => %{"x" => 1240, "y" => 150},
        "data" => %{
          "name" => "End (Approved)",
          "response_schema" => [
            %{
              "name" => "greeting",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "processed_items",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "string"}
            },
            %{
              "name" => "approval_status",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "greeting", "state_variable" => "greeting"},
            %{"response_field" => "processed_items", "state_variable" => "processed_items"},
            %{"response_field" => "approval_status", "state_variable" => "approval_status"}
          ]
        }
      },

      # ── n7: Fetch External Data (http_request) — Branch 1 ──
      %{
        "id" => "n7",
        "type" => "http_request",
        "position" => %{"x" => 780, "y" => 550},
        "data" => %{
          "name" => "Fetch External Data",
          "method" => "GET",
          "url" => "https://httpbin.org/get",
          "timeout_ms" => 5_000,
          "max_retries" => 1
        }
      },

      # ── n8: Brief Delay (delay) — Branch 1 ──
      %{
        "id" => "n8",
        "type" => "delay",
        "position" => %{"x" => 1010, "y" => 550},
        "data" => %{
          "name" => "Brief Delay",
          "duration_ms" => 500,
          "max_duration_ms" => 5_000
        }
      },

      # ── n9: Send Notification (sub_flow) — Branch 1 ──
      %{
        "id" => "n9",
        "type" => "sub_flow",
        "position" => %{"x" => 1240, "y" => 550},
        # NOTE: flow_id must be set to a real notification sub-flow UUID before execution.
        # Users should create or select a sub-flow from the properties drawer.
        "data" => %{
          "name" => "Send Notification",
          "flow_id" => "",
          "input_mapping" => %{
            "message" => ~s(state["greeting"]),
            "channel" => ~s("email")
          }
        }
      },

      # ── n10: End (Auto-Approved) — Branch 1 ──
      %{
        "id" => "n10",
        "type" => "end",
        "position" => %{"x" => 1470, "y" => 550},
        "data" => %{
          "name" => "End (Auto-Approved)",
          "response_schema" => [
            %{
              "name" => "greeting",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "processed_items",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "string"}
            },
            %{
              "name" => "approval_status",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "greeting", "state_variable" => "greeting"},
            %{"response_field" => "processed_items", "state_variable" => "processed_items"},
            %{"response_field" => "approval_status", "state_variable" => "approval_status"}
          ]
        }
      }
    ]
  end

  defp edges do
    [
      # n1 → n2
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      # n2 → n3
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0},
      # n3 port 0 → n4 (Needs Approval branch)
      %{"id" => "e3", "source" => "n3", "source_port" => 0, "target" => "n4", "target_port" => 0},
      # n4 → n5
      %{"id" => "e4", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0},
      # n5 → n6
      %{"id" => "e5", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0},
      # n3 port 1 → n7 (Auto Approve branch)
      %{"id" => "e6", "source" => "n3", "source_port" => 1, "target" => "n7", "target_port" => 0},
      # n7 → n8
      %{"id" => "e7", "source" => "n7", "source_port" => 0, "target" => "n8", "target_port" => 0},
      # n8 → n9
      %{"id" => "e8", "source" => "n8", "source_port" => 0, "target" => "n9", "target_port" => 0},
      # n9 → n10
      %{"id" => "e9", "source" => "n9", "source_port" => 0, "target" => "n10", "target_port" => 0}
    ]
  end
end
