defmodule Blackboex.Flows.Templates.SagaCompensation do
  @moduledoc """
  Saga / Distributed Transaction with Compensation template.

  Executes a multi-step transaction: reserve inventory → charge payment →
  create shipment. On any step failure, runs compensating API calls in reverse
  order to undo completed steps. This is Temporal's primary canonical pattern
  for distributed systems.

  ## Flow graph

      Start (order_id, customer_id, amount, items, simulate_failure_at?)
        → Step 1: Reserve Inventory (elixir_code — sets inventory_reserved)
        → Inventory OK? (condition: 2-way)
          → Port 0 (ok): Step 2: Charge Payment
              → Payment OK? (condition: 2-way)
                → Port 0 (ok): Step 3: Create Shipment
                    → Shipment OK? (condition: 2-way)
                      → Port 0 (ok): Complete Saga → End (Success)
                      → Port 1 (fail): Compensate: Cancel Shipment
                          → Undo Shipment API → Compensate: Refund Payment
                          → Refund API → Compensate: Release Inventory
                          → Release Inventory API → Mark Saga Failed → Fail
                → Port 1 (fail): Compensate: Refund Only → Refund API (No Shipment)
                    → Mark Saga Failed (Payment Step) → Fail (Payment Step)
          → Port 1 (fail): Mark Saga Failed (Inventory) → Fail (Inventory)
  """

  @doc "Returns the Saga Compensation flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "saga_compensation",
      name: "Saga / Distributed Transaction with Compensation",
      description:
        "Multi-step transaction with automatic rollback — reserve inventory, charge payment, create shipment",
      category: "API Infrastructure",
      icon: "hero-arrow-path",
      definition: definition()
    }
  end

  @doc false
  @spec definition() :: map()
  def definition do
    %{"version" => "1.0", "nodes" => nodes(), "edges" => edges()}
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp nodes do
    [
      # ── n1: Start ──
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 50, "y" => 300},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 60_000,
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
            %{"name" => "amount", "type" => "integer", "required" => true, "constraints" => %{}},
            %{
              "name" => "items",
              "type" => "array",
              "required" => true,
              "constraints" => %{"item_type" => "object"}
            },
            %{
              "name" => "simulate_failure_at",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "inventory_reserved",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "payment_charged",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "shipment_created",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "compensation_ran",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "failed_step",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "saga_status",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "running"
            }
          ]
        }
      },

      # ── n2: Step 1: Reserve Inventory ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 270, "y" => 300},
        "data" => %{
          "name" => "Step 1: Reserve Inventory",
          "code" => ~S"""
          if input["simulate_failure_at"] == "inventory" do
            {input, Map.put(state, "failed_step", "Inventory")}
          else
            {input, Map.put(state, "inventory_reserved", true)}
          end
          """
        }
      },

      # ── n3: Inventory OK? ──
      %{
        "id" => "n3",
        "type" => "condition",
        "position" => %{"x" => 490, "y" => 300},
        "data" => %{
          "name" => "Inventory OK?",
          "expression" => ~S"""
          if state["inventory_reserved"] == true, do: 0, else: 1
          """,
          "branch_labels" => %{"0" => "Reserved", "1" => "Failed"}
        }
      },

      # ── n4: Step 2: Charge Payment ──
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 710, "y" => 200},
        "data" => %{
          "name" => "Step 2: Charge Payment",
          "code" => ~S"""
          if input["simulate_failure_at"] == "payment" do
            {input, Map.put(state, "failed_step", "Payment")}
          else
            {input, Map.put(state, "payment_charged", true)}
          end
          """
        }
      },

      # ── n5: Payment OK? ──
      %{
        "id" => "n5",
        "type" => "condition",
        "position" => %{"x" => 930, "y" => 200},
        "data" => %{
          "name" => "Payment OK?",
          "expression" => ~S"""
          if state["payment_charged"] == true, do: 0, else: 1
          """,
          "branch_labels" => %{"0" => "Charged", "1" => "Failed"}
        }
      },

      # ── n6: Step 3: Create Shipment ──
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 1150, "y" => 100},
        "data" => %{
          "name" => "Step 3: Create Shipment",
          "code" => ~S"""
          if input["simulate_failure_at"] == "shipment" do
            {input, Map.put(state, "failed_step", "Shipment")}
          else
            {input, Map.put(state, "shipment_created", true)}
          end
          """
        }
      },

      # ── n7: Shipment OK? ──
      %{
        "id" => "n7",
        "type" => "condition",
        "position" => %{"x" => 1370, "y" => 100},
        "data" => %{
          "name" => "Shipment OK?",
          "expression" => ~S"""
          if state["shipment_created"] == true, do: 0, else: 1
          """,
          "branch_labels" => %{"0" => "Created", "1" => "Failed"}
        }
      },

      # ── n8: Complete Saga ──
      %{
        "id" => "n8",
        "type" => "elixir_code",
        "position" => %{"x" => 1590, "y" => 50},
        "data" => %{
          "name" => "Complete Saga",
          "code" => ~S"""
          {input, Map.put(state, "saga_status", "completed")}
          """
        }
      },

      # ── n9: End (Success) ──
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1790, "y" => 50},
        "data" => %{
          "name" => "End (Success)",
          "response_schema" => [
            %{
              "name" => "saga_status",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "inventory_reserved",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "payment_charged",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "shipment_created",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "saga_status", "state_variable" => "saga_status"},
            %{"response_field" => "inventory_reserved", "state_variable" => "inventory_reserved"},
            %{"response_field" => "payment_charged", "state_variable" => "payment_charged"},
            %{"response_field" => "shipment_created", "state_variable" => "shipment_created"}
          ]
        }
      },

      # ── n10: Compensate: Cancel Shipment Reservation ──
      %{
        "id" => "n10",
        "type" => "elixir_code",
        "position" => %{"x" => 1590, "y" => 200},
        "data" => %{
          "name" => "Compensate: Cancel Shipment Reservation",
          "code" => ~S"""
          {input, Map.put(state, "shipment_created", false)}
          """
        }
      },

      # ── n11: Call: Undo Shipment API ──
      %{
        "id" => "n11",
        "type" => "http_request",
        "position" => %{"x" => 1790, "y" => 200},
        "data" => %{
          "name" => "Call: Undo Shipment API",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" => ~S|{"action": "cancel_shipment", "order_id": "{{input.order_id}}"}|,
          "timeout_ms" => 10_000,
          "max_retries" => 2,
          "expected_status" => [200]
        }
      },

      # ── n12: Compensate: Refund Payment ──
      %{
        "id" => "n12",
        "type" => "elixir_code",
        "position" => %{"x" => 1990, "y" => 200},
        "data" => %{
          "name" => "Compensate: Refund Payment",
          "code" => ~S"""
          {input, Map.put(state, "payment_charged", false)}
          """
        }
      },

      # ── n13: Call: Refund API ──
      %{
        "id" => "n13",
        "type" => "http_request",
        "position" => %{"x" => 2190, "y" => 200},
        "data" => %{
          "name" => "Call: Refund API",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"action": "refund_payment", "order_id": "{{input.order_id}}", "amount": {{input.amount}}}|,
          "timeout_ms" => 10_000,
          "max_retries" => 2,
          "expected_status" => [200]
        }
      },

      # ── n14: Compensate: Release Inventory ──
      %{
        "id" => "n14",
        "type" => "elixir_code",
        "position" => %{"x" => 2390, "y" => 200},
        "data" => %{
          "name" => "Compensate: Release Inventory",
          "code" => ~S"""
          {input, Map.put(state, "inventory_reserved", false)}
          """
        }
      },

      # ── n15: Call: Release Inventory API ──
      %{
        "id" => "n15",
        "type" => "http_request",
        "position" => %{"x" => 2590, "y" => 200},
        "data" => %{
          "name" => "Call: Release Inventory API",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"action": "release_inventory", "order_id": "{{input.order_id}}"}|,
          "timeout_ms" => 10_000,
          "max_retries" => 2,
          "expected_status" => [200]
        }
      },

      # ── n16: Mark Saga Failed (Full Compensation) ──
      %{
        "id" => "n16",
        "type" => "elixir_code",
        "position" => %{"x" => 2790, "y" => 200},
        "data" => %{
          "name" => "Mark Saga Failed",
          "code" => ~S"""
          new_state =
            state
            |> Map.put("saga_status", "compensated")
            |> Map.put("compensation_ran", true)

          {input, new_state}
          """
        }
      },

      # ── n17: Saga Failed (Shipment) ──
      %{
        "id" => "n17",
        "type" => "fail",
        "position" => %{"x" => 2990, "y" => 200},
        "data" => %{
          "name" => "Saga Failed",
          "message" =>
            ~S|"Saga failed at step: #{state["failed_step"]} for order #{input["order_id"]}"|
        }
      },

      # ── n18: Compensate: Refund Only (payment charged, shipment not created) ──
      %{
        "id" => "n18",
        "type" => "elixir_code",
        "position" => %{"x" => 1150, "y" => 300},
        "data" => %{
          "name" => "Compensate: Refund Only",
          "code" => ~S"""
          {input, Map.put(state, "payment_charged", false)}
          """
        }
      },

      # ── n19: Call: Refund API (No Shipment) ──
      %{
        "id" => "n19",
        "type" => "http_request",
        "position" => %{"x" => 1370, "y" => 300},
        "data" => %{
          "name" => "Call: Refund API (No Shipment)",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"action": "refund_payment", "order_id": "{{input.order_id}}", "amount": {{input.amount}}, "shipment_existed": false}|,
          "timeout_ms" => 10_000,
          "max_retries" => 2,
          "expected_status" => [200]
        }
      },

      # ── n20: Mark Saga Failed (Payment Step) ──
      %{
        "id" => "n20",
        "type" => "elixir_code",
        "position" => %{"x" => 1590, "y" => 300},
        "data" => %{
          "name" => "Mark Saga Failed (Payment Step)",
          "code" => ~S"""
          new_state =
            state
            |> Map.put("saga_status", "compensated")
            |> Map.put("compensation_ran", true)

          {input, new_state}
          """
        }
      },

      # ── n21: Fail (Payment Step) ──
      %{
        "id" => "n21",
        "type" => "fail",
        "position" => %{"x" => 1790, "y" => 300},
        "data" => %{
          "name" => "Saga Failed (Payment Step)",
          "message" =>
            ~S|"Saga failed at step: #{state["failed_step"]} for order #{input["order_id"]}"|
        }
      },

      # ── n22: Mark Saga Failed (Inventory Step) ──
      %{
        "id" => "n22",
        "type" => "elixir_code",
        "position" => %{"x" => 710, "y" => 450},
        "data" => %{
          "name" => "Mark Saga Failed (Inventory Step)",
          "code" => ~S"""
          new_state =
            state
            |> Map.put("saga_status", "failed")
            |> Map.put("compensation_ran", false)

          {input, new_state}
          """
        }
      },

      # ── n23: Fail (Inventory Step) ──
      %{
        "id" => "n23",
        "type" => "fail",
        "position" => %{"x" => 930, "y" => 450},
        "data" => %{
          "name" => "Saga Failed (Inventory Step)",
          "message" =>
            ~S|"Saga failed at step: #{state["failed_step"]} for order #{input["order_id"]}"|
        }
      }
    ]
  end

  defp edges do
    [
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0},
      # Inventory OK → payment
      %{"id" => "e3", "source" => "n3", "source_port" => 0, "target" => "n4", "target_port" => 0},
      %{"id" => "e4", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0},
      # Inventory Failed → mark + fail
      %{
        "id" => "e5",
        "source" => "n3",
        "source_port" => 1,
        "target" => "n22",
        "target_port" => 0
      },
      %{
        "id" => "e6",
        "source" => "n22",
        "source_port" => 0,
        "target" => "n23",
        "target_port" => 0
      },
      # Payment OK → shipment
      %{"id" => "e7", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0},
      %{"id" => "e8", "source" => "n6", "source_port" => 0, "target" => "n7", "target_port" => 0},
      # Payment Failed → refund only compensation
      %{
        "id" => "e9",
        "source" => "n5",
        "source_port" => 1,
        "target" => "n18",
        "target_port" => 0
      },
      %{
        "id" => "e10",
        "source" => "n18",
        "source_port" => 0,
        "target" => "n19",
        "target_port" => 0
      },
      %{
        "id" => "e11",
        "source" => "n19",
        "source_port" => 0,
        "target" => "n20",
        "target_port" => 0
      },
      %{
        "id" => "e12",
        "source" => "n20",
        "source_port" => 0,
        "target" => "n21",
        "target_port" => 0
      },
      # Shipment OK → complete saga
      %{
        "id" => "e13",
        "source" => "n7",
        "source_port" => 0,
        "target" => "n8",
        "target_port" => 0
      },
      %{
        "id" => "e14",
        "source" => "n8",
        "source_port" => 0,
        "target" => "n9",
        "target_port" => 0
      },
      # Shipment Failed → full compensation chain
      %{
        "id" => "e15",
        "source" => "n7",
        "source_port" => 1,
        "target" => "n10",
        "target_port" => 0
      },
      %{
        "id" => "e16",
        "source" => "n10",
        "source_port" => 0,
        "target" => "n11",
        "target_port" => 0
      },
      %{
        "id" => "e17",
        "source" => "n11",
        "source_port" => 0,
        "target" => "n12",
        "target_port" => 0
      },
      %{
        "id" => "e18",
        "source" => "n12",
        "source_port" => 0,
        "target" => "n13",
        "target_port" => 0
      },
      %{
        "id" => "e19",
        "source" => "n13",
        "source_port" => 0,
        "target" => "n14",
        "target_port" => 0
      },
      %{
        "id" => "e20",
        "source" => "n14",
        "source_port" => 0,
        "target" => "n15",
        "target_port" => 0
      },
      %{
        "id" => "e21",
        "source" => "n15",
        "source_port" => 0,
        "target" => "n16",
        "target_port" => 0
      },
      %{
        "id" => "e22",
        "source" => "n16",
        "source_port" => 0,
        "target" => "n17",
        "target_port" => 0
      }
    ]
  end
end
