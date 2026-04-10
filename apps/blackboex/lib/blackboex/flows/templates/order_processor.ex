defmodule Blackboex.Flows.Templates.OrderProcessor do
  @moduledoc """
  Order Processor template.

  A 3-way branching flow that routes orders by priority and calculates
  shipping/pricing differently per branch. Tests multi-branch conditions
  with business logic in each path.

  ## Flow graph

      Start (item, quantity, priority)
        → Calculate Base (elixir_code)
        → Route by Priority (condition: 3-way)
          → Port 0: Express Processing (elixir_code) → End (Express)
          → Port 1: Standard Processing (elixir_code) → End (Standard)
          → Port 2: Invalid Order (elixir_code) → End (Error)
  """

  @doc "Returns the Order Processor flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "order_processor",
      name: "Order Processor",
      description:
        "A 3-way branching flow that routes orders by priority — tests multi-branch conditions with business logic",
      category: "Integrations",
      icon: "hero-shopping-cart",
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
        "position" => %{"x" => 50, "y" => 300},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 10_000,
          "payload_schema" => [
            %{
              "name" => "item",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "quantity",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "priority",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            }
          ],
          "state_schema" => [
            %{
              "name" => "base_price",
              "type" => "float",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0.0
            },
            %{
              "name" => "shipping",
              "type" => "float",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0.0
            },
            %{
              "name" => "total",
              "type" => "float",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0.0
            },
            %{
              "name" => "status",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "pending"
            },
            %{
              "name" => "delivery_days",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            }
          ]
        }
      },

      # ── n2: Calculate Base Price ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 280, "y" => 300},
        "data" => %{
          "name" => "Calculate Base",
          "code" => ~S"""
          quantity = input["quantity"]
          base_price = quantity * 10.0
          {input, Map.put(state, "base_price", base_price)}
          """
        }
      },

      # ── n3: Route by Priority ──
      %{
        "id" => "n3",
        "type" => "condition",
        "position" => %{"x" => 510, "y" => 300},
        "data" => %{
          "name" => "Route by Priority",
          "expression" => ~S"""
          case input["priority"] do
            "express" -> 0
            "standard" -> 1
            _ -> 2
          end
          """,
          "branch_labels" => %{
            "0" => "Express",
            "1" => "Standard",
            "2" => "Invalid"
          }
        }
      },

      # ── n4: Express Processing ──
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 780, "y" => 100},
        "data" => %{
          "name" => "Express Processing",
          "code" => ~S"""
          base = state["base_price"]
          shipping = 25.0
          total = base + shipping

          new_state = state
            |> Map.put("shipping", shipping)
            |> Map.put("total", total)
            |> Map.put("status", "express_confirmed")
            |> Map.put("delivery_days", 1)

          {input, new_state}
          """
        }
      },

      # ── n5: Standard Processing ──
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 780, "y" => 300},
        "data" => %{
          "name" => "Standard Processing",
          "code" => ~S"""
          base = state["base_price"]
          shipping = 5.0
          total = base + shipping

          new_state = state
            |> Map.put("shipping", shipping)
            |> Map.put("total", total)
            |> Map.put("status", "standard_confirmed")
            |> Map.put("delivery_days", 5)

          {input, new_state}
          """
        }
      },

      # ── n6: Invalid Order ──
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 780, "y" => 500},
        "data" => %{
          "name" => "Invalid Order",
          "code" => ~S"""
          new_state = state
            |> Map.put("status", "rejected")
            |> Map.put("total", 0.0)

          {%{"error" => "Invalid priority: #{input["priority"]}"}, new_state}
          """
        }
      },

      # ── End nodes ──
      %{
        "id" => "n7",
        "type" => "end",
        "position" => %{"x" => 1050, "y" => 100},
        "data" => %{
          "name" => "End (Express)",
          "response_schema" => [
            %{"name" => "status", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "total", "type" => "float", "required" => true, "constraints" => %{}},
            %{
              "name" => "delivery_days",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "status", "state_variable" => "status"},
            %{"response_field" => "total", "state_variable" => "total"},
            %{"response_field" => "delivery_days", "state_variable" => "delivery_days"}
          ]
        }
      },
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1050, "y" => 300},
        "data" => %{
          "name" => "End (Standard)",
          "response_schema" => [
            %{"name" => "status", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "total", "type" => "float", "required" => true, "constraints" => %{}},
            %{
              "name" => "delivery_days",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "status", "state_variable" => "status"},
            %{"response_field" => "total", "state_variable" => "total"},
            %{"response_field" => "delivery_days", "state_variable" => "delivery_days"}
          ]
        }
      },
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1050, "y" => 500},
        "data" => %{"name" => "End (Error)"}
      }
    ]
  end

  defp edges do
    [
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0},
      %{"id" => "e3", "source" => "n3", "source_port" => 0, "target" => "n4", "target_port" => 0},
      %{"id" => "e4", "source" => "n3", "source_port" => 1, "target" => "n5", "target_port" => 0},
      %{"id" => "e5", "source" => "n3", "source_port" => 2, "target" => "n6", "target_port" => 0},
      %{"id" => "e6", "source" => "n4", "source_port" => 0, "target" => "n7", "target_port" => 0},
      %{"id" => "e7", "source" => "n5", "source_port" => 0, "target" => "n8", "target_port" => 0},
      %{"id" => "e8", "source" => "n6", "source_port" => 0, "target" => "n9", "target_port" => 0}
    ]
  end
end
