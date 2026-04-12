defmodule Blackboex.Flows.Templates.SubFlowOrchestrator do
  @moduledoc """
  Sub-flow Orchestrator template — demonstrates flow composition patterns.

  A parent "Order Processing" flow invokes two separate child flows: one for
  payment validation and one for inventory check, then aggregates results.
  Shows how to build modular, composable flows.

  ## On sub_flow nodes

  The `sub_flow` node requires a live `flow_id` UUID at runtime (assigned when
  you deploy a child flow). Since templates cannot embed UUIDs, this template
  simulates sub-flow behavior with `elixir_code` nodes that replicate what the
  child flows would do.

  **To convert to real sub_flow nodes in production:**
  1. Create and deploy "Payment Validator" and "Inventory Checker" child flows
  2. Replace `n2` with:
     ```
     %{"type" => "sub_flow", "data" => %{"flow_id" => "<payment_validator_uuid>", ...}}
     ```
  3. Replace `n4` with:
     ```
     %{"type" => "sub_flow", "data" => %{"flow_id" => "<inventory_checker_uuid>", ...}}
     ```

  ## Flow graph

      Start (order_id, customer_id, items, total_amount)
        → Invoke: Validate Payment (simulated sub-flow)
        → Payment Valid? (condition: 2-way)
          → Port 0 (valid): Invoke: Check Inventory (simulated sub-flow)
              → Inventory Available? (condition: 2-way)
                → Port 0 (available): Aggregate Results → End (Order Confirmed)
                → Port 1 (hold):      Inventory Unavailable → End (Inventory Hold)
          → Port 1 (failed): Payment Failed (elixir_code) → Fail (Payment Validation)
  """

  @doc "Returns the Sub-flow Orchestrator flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "sub_flow_orchestrator",
      name: "Sub-flow Orchestrator",
      description:
        "Demonstrates flow composition — parent flow coordinates payment and inventory child flows",
      category: "Getting Started",
      icon: "hero-squares-2x2",
      definition: definition()
    }
  end

  @doc false
  @spec definition() :: map()
  def definition do
    %{"version" => "1.0", "nodes" => nodes(), "edges" => edges()}
  end

  defp nodes do
    [
      # ── n1: Start ──
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 50, "y" => 250},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 30_000,
          "payload_schema" => [
            %{
              "name" => "order_id",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "customer_id",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "items",
              "type" => "array",
              "required" => true,
              "constraints" => %{"item_type" => "object"}
            },
            %{
              "name" => "total_amount",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "payment_valid",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "inventory_available",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "order_status",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "pending"
            },
            %{
              "name" => "payment_result",
              "type" => "object",
              "required" => false,
              "constraints" => %{},
              "initial_value" => %{}
            },
            %{
              "name" => "inventory_result",
              "type" => "object",
              "required" => false,
              "constraints" => %{},
              "initial_value" => %{}
            }
          ]
        }
      },

      # ── n2: Invoke: Validate Payment (Sub-flow simulation) ──
      # In production: replace with sub_flow node pointing to "payment_validator" flow.
      # The child flow would receive: customer_id, amount → returns: valid (bool), reason (str)
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 270, "y" => 250},
        "data" => %{
          "name" => "Invoke: Validate Payment (Sub-flow)",
          "code" => ~S"""
          # Simulates: sub_flow "payment_validator"
          # Child flow input: customer_id, amount
          # Child flow output: valid, reason
          valid = input["total_amount"] > 0 and input["customer_id"] != nil and
                  input["customer_id"] != ""

          payment_result = %{
            "valid" => valid,
            "reason" => if(valid, do: "Payment authorized", else: "Invalid amount or customer"),
            "provider" => "stripe",
            "simulated" => true
          }

          new_state =
            state
            |> Map.put("payment_valid", valid)
            |> Map.put("payment_result", payment_result)

          {input, new_state}
          """
        }
      },

      # ── n3: Payment Valid? ──
      %{
        "id" => "n3",
        "type" => "condition",
        "position" => %{"x" => 490, "y" => 250},
        "data" => %{
          "name" => "Payment Valid?",
          "expression" => ~S"""
          if state["payment_valid"] == true, do: 0, else: 1
          """,
          "branch_labels" => %{"0" => "Valid", "1" => "Failed"}
        }
      },

      # ── n4: Invoke: Check Inventory (Sub-flow simulation) ──
      # In production: replace with sub_flow node pointing to "inventory_checker" flow.
      # The child flow would receive: items → returns: available (bool), shortage_items (list)
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 710, "y" => 150},
        "data" => %{
          "name" => "Invoke: Check Inventory (Sub-flow)",
          "code" => ~S"""
          # Simulates: sub_flow "inventory_checker"
          # Child flow input: items
          # Child flow output: available, shortage_items
          items = input["items"] || []
          available = length(items) > 0

          inventory_result = %{
            "available" => available,
            "shortage_items" => if(available, do: [], else: ["no_items"]),
            "warehouse" => "wh-us-east-1",
            "simulated" => true
          }

          new_state =
            state
            |> Map.put("inventory_available", available)
            |> Map.put("inventory_result", inventory_result)

          {input, new_state}
          """
        }
      },

      # ── n5: Inventory Available? ──
      %{
        "id" => "n5",
        "type" => "condition",
        "position" => %{"x" => 930, "y" => 150},
        "data" => %{
          "name" => "Inventory Available?",
          "expression" => ~S"""
          if state["inventory_available"] == true, do: 0, else: 1
          """,
          "branch_labels" => %{"0" => "Available", "1" => "Hold"}
        }
      },

      # ── n6: Aggregate Results ──
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 1150, "y" => 80},
        "data" => %{
          "name" => "Aggregate Results",
          "code" => ~S"""
          new_state = Map.put(state, "order_status", "confirmed")
          {input, new_state}
          """
        }
      },

      # ── n7: End (Order Confirmed) ──
      %{
        "id" => "n7",
        "type" => "end",
        "position" => %{"x" => 1370, "y" => 80},
        "data" => %{
          "name" => "End (Order Confirmed)",
          "response_schema" => [
            %{
              "name" => "order_status",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "payment_valid",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "inventory_available",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "payment_result",
              "type" => "object",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "inventory_result",
              "type" => "object",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "order_status", "state_variable" => "order_status"},
            %{"response_field" => "payment_valid", "state_variable" => "payment_valid"},
            %{
              "response_field" => "inventory_available",
              "state_variable" => "inventory_available"
            },
            %{"response_field" => "payment_result", "state_variable" => "payment_result"},
            %{"response_field" => "inventory_result", "state_variable" => "inventory_result"}
          ]
        }
      },

      # ── n8: Inventory Unavailable ──
      %{
        "id" => "n8",
        "type" => "elixir_code",
        "position" => %{"x" => 1150, "y" => 230},
        "data" => %{
          "name" => "Inventory Unavailable",
          "code" => ~S"""
          {input, Map.put(state, "order_status", "inventory_hold")}
          """
        }
      },

      # ── n9: End (Inventory Hold) ──
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1370, "y" => 230},
        "data" => %{
          "name" => "End (Inventory Hold)",
          "response_schema" => [
            %{
              "name" => "order_status",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "payment_valid",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "inventory_available",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "order_status", "state_variable" => "order_status"},
            %{"response_field" => "payment_valid", "state_variable" => "payment_valid"},
            %{
              "response_field" => "inventory_available",
              "state_variable" => "inventory_available"
            }
          ]
        }
      },

      # ── n10: Payment Failed ──
      %{
        "id" => "n10",
        "type" => "elixir_code",
        "position" => %{"x" => 710, "y" => 380},
        "data" => %{
          "name" => "Payment Failed",
          "code" => ~S"""
          {input, Map.put(state, "order_status", "payment_failed")}
          """
        }
      },

      # ── n11: Fail (Payment Validation) ──
      %{
        "id" => "n11",
        "type" => "fail",
        "position" => %{"x" => 930, "y" => 380},
        "data" => %{
          "name" => "Payment Validation Failed",
          "message" => ~S|"Payment validation failed for order #{input["order_id"]}"|
        }
      }
    ]
  end

  defp edges do
    [
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0},
      # Payment valid → check inventory
      %{"id" => "e3", "source" => "n3", "source_port" => 0, "target" => "n4", "target_port" => 0},
      %{"id" => "e4", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0},
      # Inventory available → confirmed
      %{"id" => "e5", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0},
      %{"id" => "e6", "source" => "n6", "source_port" => 0, "target" => "n7", "target_port" => 0},
      # Inventory hold
      %{"id" => "e7", "source" => "n5", "source_port" => 1, "target" => "n8", "target_port" => 0},
      %{"id" => "e8", "source" => "n8", "source_port" => 0, "target" => "n9", "target_port" => 0},
      # Payment failed
      %{
        "id" => "e9",
        "source" => "n3",
        "source_port" => 1,
        "target" => "n10",
        "target_port" => 0
      },
      %{
        "id" => "e10",
        "source" => "n10",
        "source_port" => 0,
        "target" => "n11",
        "target_port" => 0
      }
    ]
  end
end
