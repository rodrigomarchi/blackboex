defmodule Blackboex.Flows.Templates.AbandonedCartRecovery do
  @moduledoc """
  Abandoned Cart Recovery template.

  E-commerce pipeline: calculates a discount based on cart total, schedules
  reminder/final-offer messages via delay steps, and short-circuits if the
  customer has already purchased.

  ## Flow graph

      Start → Calculate Discount → Wait Before Reminder → Send Reminder → Already Purchased?
        → 0: Apply Discount → Wait Before Final → Send Final Offer → End (Recovery Sent)
        → 1: No Action Needed → End (No Action)
  """

  @doc "Returns the Abandoned Cart Recovery flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "abandoned_cart_recovery",
      name: "Abandoned Cart Recovery",
      description: "Sends reminders and discount offers to recover abandoned shopping carts",
      category: "E-commerce",
      icon: "hero-shopping-cart",
      definition: definition()
    }
  end

  @doc false
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
              "name" => "customer_name",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "customer_email",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "cart_total",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "cart_items",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "string"}
            },
            %{
              "name" => "already_purchased",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "discount_percent",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "reminder_sent",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "final_offer_sent",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "recovered",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "step",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "start"
            }
          ]
        }
      },
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 260, "y" => 250},
        "data" => %{
          "name" => "Calculate Discount",
          "code" => ~S"""
          total = input["cart_total"] || 0

          discount =
            cond do
              total >= 10_000 -> 15
              total >= 5_000 -> 10
              true -> 5
            end

          new_state = state
            |> Map.put("discount_percent", discount)
            |> Map.put("step", "calculated")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n3",
        "type" => "delay",
        "position" => %{"x" => 470, "y" => 250},
        "data" => %{
          "name" => "Wait Before Reminder",
          "duration_ms" => 10,
          "max_duration_ms" => 1_000
        }
      },
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 680, "y" => 250},
        "data" => %{
          "name" => "Send Reminder",
          "code" => ~S"""
          new_state = state
            |> Map.put("reminder_sent", true)
            |> Map.put("step", "reminded")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n5",
        "type" => "condition",
        "position" => %{"x" => 890, "y" => 250},
        "data" => %{
          "name" => "Already Purchased?",
          "expression" => ~S|if input["already_purchased"] == true, do: 1, else: 0|,
          "branch_labels" => %{
            "0" => "Still Abandoned",
            "1" => "Purchased"
          }
        }
      },
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 1100, "y" => 120},
        "data" => %{
          "name" => "Apply Discount",
          "code" => ~S"""
          new_state = Map.put(state, "step", "discount_applied")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n7",
        "type" => "delay",
        "position" => %{"x" => 1310, "y" => 120},
        "data" => %{
          "name" => "Wait Before Final",
          "duration_ms" => 10,
          "max_duration_ms" => 1_000
        }
      },
      %{
        "id" => "n8",
        "type" => "elixir_code",
        "position" => %{"x" => 1520, "y" => 120},
        "data" => %{
          "name" => "Send Final Offer",
          "code" => ~S"""
          new_state = state
            |> Map.put("final_offer_sent", true)
            |> Map.put("step", "final_offer")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1730, "y" => 120},
        "data" => %{
          "name" => "End (Recovery Sent)",
          "response_schema" => [
            %{
              "name" => "discount_percent",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "reminder_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "final_offer_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "step", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "discount_percent", "state_variable" => "discount_percent"},
            %{"response_field" => "reminder_sent", "state_variable" => "reminder_sent"},
            %{"response_field" => "final_offer_sent", "state_variable" => "final_offer_sent"},
            %{"response_field" => "step", "state_variable" => "step"}
          ]
        }
      },
      %{
        "id" => "n10",
        "type" => "elixir_code",
        "position" => %{"x" => 1100, "y" => 400},
        "data" => %{
          "name" => "No Action Needed",
          "code" => ~S"""
          new_state = state
            |> Map.put("recovered", true)
            |> Map.put("step", "already_purchased")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n11",
        "type" => "end",
        "position" => %{"x" => 1310, "y" => 400},
        "data" => %{
          "name" => "End (No Action)",
          "response_schema" => [
            %{
              "name" => "discount_percent",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "reminder_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "recovered",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "step", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "discount_percent", "state_variable" => "discount_percent"},
            %{"response_field" => "reminder_sent", "state_variable" => "reminder_sent"},
            %{"response_field" => "recovered", "state_variable" => "recovered"},
            %{"response_field" => "step", "state_variable" => "step"}
          ]
        }
      }
    ]
  end

  defp edges do
    [
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0},
      %{"id" => "e3", "source" => "n3", "source_port" => 0, "target" => "n4", "target_port" => 0},
      %{"id" => "e4", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0},
      %{"id" => "e5", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0},
      %{"id" => "e6", "source" => "n6", "source_port" => 0, "target" => "n7", "target_port" => 0},
      %{"id" => "e7", "source" => "n7", "source_port" => 0, "target" => "n8", "target_port" => 0},
      %{"id" => "e8", "source" => "n8", "source_port" => 0, "target" => "n9", "target_port" => 0},
      %{
        "id" => "e9",
        "source" => "n5",
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
