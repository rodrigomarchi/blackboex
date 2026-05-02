defmodule Blackboex.Samples.FlowTemplates.WebhookProcessor do
  @moduledoc """
  Webhook Event Processor template.

  A real-world webhook event processing pipeline that receives webhook events,
  validates them, and routes processing based on event type, with debug logging
  and error handling.

  ## Flow graph

      Start → Debug: Log Event → Validate Event (skippable) → Route by Type (3-way)
        → Branch 0 (order):   Process Order → Delay → End (Order)
        → Branch 1 (payment): Process Payment → End (Payment)
        → Branch 2 (unknown): Fail
  """

  @doc "Returns the Webhook Processor flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "webhook_processor",
      name: "Webhook Processor",
      description:
        "Real-world webhook event processing pipeline with validation, routing, and error handling",
      category: "Advanced",
      icon: "hero-arrow-path",
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
              "name" => "event_type",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "payload",
              "type" => "object",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "timestamp",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "event_type",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "processed",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
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

      # ── n2: Debug: Log Event ──
      %{
        "id" => "n2",
        "type" => "debug",
        "position" => %{"x" => 250, "y" => 250},
        "data" => %{
          "name" => "Debug: Log Event",
          "expression" =>
            ~S|%{"type" => input["event_type"], "timestamp" => input["timestamp"], "has_payload" => input["payload"] != nil}|,
          "log_level" => "info",
          "state_key" => "debug_event"
        }
      },

      # ── n3: Validate Event (with skip_condition) ──
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 450, "y" => 250},
        "data" => %{
          "name" => "Validate Event",
          "skip_condition" => ~S|input["event_type"] == "test"|,
          "code" => ~S"""
          event_type = input["event_type"]
          valid_types = ["order.created", "payment.received", "test"]

          if event_type in valid_types do
            result = %{"event_type" => event_type, "payload" => input["payload"], "valid" => true}
            {result, Map.put(state, "event_type", event_type)}
          else
            result = %{"event_type" => event_type, "valid" => false, "error" => "Unknown event type: #{event_type}"}
            {result, Map.put(state, "event_type", event_type)}
          end
          """
        }
      },

      # ── n4: Route by Type (3-way condition) ──
      %{
        "id" => "n4",
        "type" => "condition",
        "position" => %{"x" => 650, "y" => 250},
        "data" => %{
          "name" => "Route by Type",
          "expression" => ~S"""
          cond do
            input["event_type"] == "order.created" or input["event_type"] == "test" -> 0
            input["event_type"] == "payment.received" -> 1
            true -> 2
          end
          """,
          "branch_labels" => %{
            "0" => "Order",
            "1" => "Payment",
            "2" => "Unknown"
          }
        }
      },

      # ── n5: Process Order (Branch 0) ──
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 100},
        "data" => %{
          "name" => "Process Order",
          "code" => ~S"""
          payload = input["payload"] || %{}
          result = %{
            "action" => "order_processed",
            "order_id" => payload["id"] || "unknown",
            "amount" => payload["amount"] || 0
          }
          {result, Map.put(state, "processed", true)}
          """
        }
      },

      # ── n6: Delay (Branch 0, after Process Order) ──
      %{
        "id" => "n6",
        "type" => "delay",
        "position" => %{"x" => 1100, "y" => 100},
        "data" => %{
          "name" => "Delay",
          "duration_ms" => 10,
          "max_duration_ms" => 1_000
        }
      },

      # ── n7: End (Order) ──
      %{
        "id" => "n7",
        "type" => "end",
        "position" => %{"x" => 1300, "y" => 100},
        "data" => %{"name" => "End (Order)"}
      },

      # ── n8: Process Payment (Branch 1) ──
      %{
        "id" => "n8",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 300},
        "data" => %{
          "name" => "Process Payment",
          "code" => ~S"""
          payload = input["payload"] || %{}
          result = %{
            "action" => "payment_processed",
            "payment_id" => payload["id"] || "unknown",
            "status" => "confirmed"
          }
          {result, Map.put(state, "processed", true)}
          """
        }
      },

      # ── n9: End (Payment) ──
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1100, "y" => 300},
        "data" => %{"name" => "End (Payment)"}
      },

      # ── n10: Fail (Branch 2 — Unknown event type) ──
      %{
        "id" => "n10",
        "type" => "fail",
        "position" => %{"x" => 900, "y" => 500},
        "data" => %{
          "name" => "Fail",
          "message" =>
            ~S("Unsupported event type: #{input["event_type"] || state["event_type"]}"),
          "include_state" => false
        }
      }
    ]
  end

  defp edges do
    [
      # Start → Debug: Log Event
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      # Debug: Log Event → Validate Event
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0},
      # Validate Event → Route by Type
      %{"id" => "e3", "source" => "n3", "source_port" => 0, "target" => "n4", "target_port" => 0},
      # Route by Type → Process Order (port 0)
      %{"id" => "e4", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0},
      # Route by Type → Process Payment (port 1)
      %{"id" => "e5", "source" => "n4", "source_port" => 1, "target" => "n8", "target_port" => 0},
      # Route by Type → Fail (port 2)
      %{
        "id" => "e6",
        "source" => "n4",
        "source_port" => 2,
        "target" => "n10",
        "target_port" => 0
      },
      # Process Order → Delay
      %{"id" => "e7", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0},
      # Delay → End (Order)
      %{"id" => "e8", "source" => "n6", "source_port" => 0, "target" => "n7", "target_port" => 0},
      # Process Payment → End (Payment)
      %{"id" => "e9", "source" => "n8", "source_port" => 0, "target" => "n9", "target_port" => 0}
    ]
  end
end
