defmodule Blackboex.Flows.Templates.StripePaymentRouter do
  @moduledoc """
  Stripe Payment Router template.

  Routes Stripe-style payment webhook events (payment.succeeded, payment.failed,
  charge.disputed) to dedicated processing branches. Demonstrates debug logging,
  4-way condition routing, delay-based retry cooldowns, and fail branches for
  unknown events.

  ## Flow graph

      Start → Debug Event → Validate Event → Route by Event (4-way)
        → 0 (succeeded): Process Success → End (Success)
        → 1 (failed):    Process Failure → Retry Cooldown → End (Failed)
        → 2 (disputed):  Process Dispute → End (Disputed)
        → 3 (unknown):   Fail
  """

  @doc "Returns the Stripe Payment Router flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "stripe_payment_router",
      name: "Stripe Payment Router",
      description:
        "Routes Stripe-style payment webhook events through success/failure/dispute branches",
      category: "Payments & Billing",
      icon: "hero-credit-card",
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
              "name" => "event_type",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "payment_id",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "amount",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "customer_id",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "metadata",
              "type" => "object",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "status",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "pending"
            },
            %{
              "name" => "action",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "processed_at",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "retry_count",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "debug_event",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => nil
            }
          ]
        }
      },
      %{
        "id" => "n2",
        "type" => "debug",
        "position" => %{"x" => 260, "y" => 250},
        "data" => %{
          "name" => "Debug Event",
          "expression" =>
            ~S|%{"event_type" => input["event_type"], "payment_id" => input["payment_id"], "amount" => input["amount"]}|,
          "log_level" => "info",
          "state_key" => "debug_event"
        }
      },
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 470, "y" => 250},
        "data" => %{
          "name" => "Validate Event",
          "code" => ~S"""
          known = ["payment.succeeded", "payment.failed", "charge.disputed"]
          event_type = input["event_type"]
          new_state = Map.put(state, "processed_at", "2026-04-10T00:00:00Z")
          result = %{
            "event_type" => event_type,
            "payment_id" => input["payment_id"],
            "amount" => input["amount"],
            "customer_id" => input["customer_id"],
            "known" => event_type in known
          }
          {result, new_state}
          """
        }
      },
      %{
        "id" => "n4",
        "type" => "condition",
        "position" => %{"x" => 680, "y" => 250},
        "data" => %{
          "name" => "Route by Event",
          "expression" => ~S"""
          cond do
            input["event_type"] == "payment.succeeded" -> 0
            input["event_type"] == "payment.failed" -> 1
            input["event_type"] == "charge.disputed" -> 2
            true -> 3
          end
          """,
          "branch_labels" => %{
            "0" => "Succeeded",
            "1" => "Failed",
            "2" => "Disputed",
            "3" => "Unknown"
          }
        }
      },
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 80},
        "data" => %{
          "name" => "Process Success",
          "code" => ~S"""
          new_state = state
            |> Map.put("status", "succeeded")
            |> Map.put("action", "fulfill_order")
          result = Map.put(input, "status", "succeeded")
          {result, new_state}
          """
        }
      },
      %{
        "id" => "n6",
        "type" => "end",
        "position" => %{"x" => 1120, "y" => 80},
        "data" => %{
          "name" => "End (Success)",
          "response_schema" => [
            %{"name" => "status", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "action", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "payment_id",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "status", "state_variable" => "status"},
            %{"response_field" => "action", "state_variable" => "action"}
          ]
        }
      },
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 260},
        "data" => %{
          "name" => "Process Failure",
          "code" => ~S"""
          new_state = state
            |> Map.put("status", "failed")
            |> Map.put("action", "retry_payment")
            |> Map.put("retry_count", (state["retry_count"] || 0) + 1)
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n8",
        "type" => "delay",
        "position" => %{"x" => 1120, "y" => 260},
        "data" => %{
          "name" => "Retry Cooldown",
          "duration_ms" => 10,
          "max_duration_ms" => 1_000
        }
      },
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1340, "y" => 260},
        "data" => %{
          "name" => "End (Failed)",
          "response_schema" => [
            %{"name" => "status", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "action", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "status", "state_variable" => "status"},
            %{"response_field" => "action", "state_variable" => "action"}
          ]
        }
      },
      %{
        "id" => "n10",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 440},
        "data" => %{
          "name" => "Process Dispute",
          "code" => ~S"""
          new_state = state
            |> Map.put("status", "disputed")
            |> Map.put("action", "create_case")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n11",
        "type" => "end",
        "position" => %{"x" => 1120, "y" => 440},
        "data" => %{
          "name" => "End (Disputed)",
          "response_schema" => [
            %{"name" => "status", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "action", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "status", "state_variable" => "status"},
            %{"response_field" => "action", "state_variable" => "action"}
          ]
        }
      },
      %{
        "id" => "n12",
        "type" => "fail",
        "position" => %{"x" => 900, "y" => 600},
        "data" => %{
          "name" => "Unknown Event",
          "message" => ~S|"Unknown payment event: #{input["event_type"]}"|,
          "include_state" => false
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
      %{"id" => "e6", "source" => "n4", "source_port" => 1, "target" => "n7", "target_port" => 0},
      %{"id" => "e7", "source" => "n7", "source_port" => 0, "target" => "n8", "target_port" => 0},
      %{"id" => "e8", "source" => "n8", "source_port" => 0, "target" => "n9", "target_port" => 0},
      %{
        "id" => "e9",
        "source" => "n4",
        "source_port" => 2,
        "target" => "n10",
        "target_port" => 0
      },
      %{
        "id" => "e10",
        "source" => "n10",
        "source_port" => 0,
        "target" => "n11",
        "target_port" => 0
      },
      %{
        "id" => "e11",
        "source" => "n4",
        "source_port" => 3,
        "target" => "n12",
        "target_port" => 0
      }
    ]
  end
end
