defmodule Blackboex.Samples.FlowTemplates.SlaMonitor do
  @moduledoc """
  SLA Breach Monitor template.

  Receives a list of open support tickets, iterates over them with for_each
  to identify SLA breaches based on ticket age vs. priority threshold, then
  sends a breach report if any are found. Distinct from escalation_approval —
  this is time-SLA-gated (automatic), not human-approval-gated.

  ## Flow graph

      Start (tickets: array, sla_thresholds?: object)
        → Init Report (elixir_code — set total_tickets, report_generated_at)
        → Check Each Ticket (for_each — compute breach per ticket → state.processed)
        → Aggregate Breaches (elixir_code — count breached, set breached_count)
        → Any Breaches? (condition: 2-way)
          → Port 0 (breaches found): Send Breach Report (http_request) → End (Breaches Found)
          → Port 1 (all clear):      End (All Clear)
  """

  @doc "Returns the SLA Monitor flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "sla_monitor",
      name: "SLA Breach Monitor",
      description:
        "Scans open tickets for SLA breaches by priority threshold and sends a breach report",
      category: "DevOps & Monitoring",
      icon: "hero-clock",
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
              "name" => "tickets",
              "type" => "array",
              "required" => true,
              "constraints" => %{"item_type" => "object"}
            },
            %{
              "name" => "sla_thresholds",
              "type" => "object",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "total_tickets",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "breached_count",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "processed",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "object"},
              "initial_value" => []
            },
            %{
              "name" => "report_generated_at",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "sla_thresholds",
              "type" => "object",
              "required" => false,
              "constraints" => %{},
              "initial_value" => %{}
            }
          ]
        }
      },

      # ── n2: Init Report ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 270, "y" => 250},
        "data" => %{
          "name" => "Init Report",
          "code" => ~S"""
          tickets = input["tickets"] || []
          thresholds = input["sla_thresholds"] || %{"critical" => 1, "high" => 4, "normal" => 24}
          ts = DateTime.utc_now() |> DateTime.to_iso8601()

          new_state =
            state
            |> Map.put("total_tickets", length(tickets))
            |> Map.put("report_generated_at", ts)
            |> Map.put("sla_thresholds", thresholds)

          {input, new_state}
          """
        }
      },

      # ── n3: Check Each Ticket (for_each) ──
      %{
        "id" => "n3",
        "type" => "for_each",
        "position" => %{"x" => 490, "y" => 250},
        "data" => %{
          "name" => "Check Each Ticket",
          "source_expression" => ~S'input["tickets"] || []',
          "body_code" => ~S"""
          thresholds = state["sla_thresholds"] || %{"critical" => 1, "high" => 4, "normal" => 24}
          priority = item["priority"] || "normal"
          threshold = Map.get(thresholds, priority, 24)
          age = item["age_hours"] || 0
          breached = age > threshold

          Map.put(item, "breached", breached)
          """,
          "item_variable" => "item",
          "accumulator" => "processed",
          "batch_size" => 50
        }
      },

      # ── n4: Aggregate Breaches ──
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 710, "y" => 250},
        "data" => %{
          "name" => "Aggregate Breaches",
          "code" => ~S"""
          processed = state["processed"] || []
          breached = Enum.count(processed, fn t -> t["breached"] == true end)
          {input, Map.put(state, "breached_count", breached)}
          """
        }
      },

      # ── n5: Any Breaches? (2-way condition) ──
      %{
        "id" => "n5",
        "type" => "condition",
        "position" => %{"x" => 930, "y" => 250},
        "data" => %{
          "name" => "Any Breaches?",
          "expression" => ~S"""
          if state["breached_count"] > 0, do: 0, else: 1
          """,
          "branch_labels" => %{
            "0" => "Breaches Found",
            "1" => "All Clear"
          }
        }
      },

      # ── n6: Send Breach Report ──
      %{
        "id" => "n6",
        "type" => "http_request",
        "position" => %{"x" => 1150, "y" => 100},
        "data" => %{
          "name" => "Send Breach Report",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"alert": "SLA Breach", "breached_count": {{state.breached_count}}, "total_tickets": {{state.total_tickets}}, "generated_at": "{{state.report_generated_at}}"}|,
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n7: End (Breaches Found) ──
      %{
        "id" => "n7",
        "type" => "end",
        "position" => %{"x" => 1370, "y" => 100},
        "data" => %{
          "name" => "End (Breaches Found)",
          "response_schema" => [
            %{
              "name" => "total_tickets",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "breached_count",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "report_generated_at",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "total_tickets", "state_variable" => "total_tickets"},
            %{"response_field" => "breached_count", "state_variable" => "breached_count"},
            %{
              "response_field" => "report_generated_at",
              "state_variable" => "report_generated_at"
            }
          ]
        }
      },

      # ── n8: End (All Clear) ──
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1150, "y" => 400},
        "data" => %{
          "name" => "End (All Clear)",
          "response_schema" => [
            %{
              "name" => "total_tickets",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "breached_count",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "report_generated_at",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "total_tickets", "state_variable" => "total_tickets"},
            %{"response_field" => "breached_count", "state_variable" => "breached_count"},
            %{
              "response_field" => "report_generated_at",
              "state_variable" => "report_generated_at"
            }
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
      # Breaches found branch
      %{"id" => "e5", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0},
      %{"id" => "e6", "source" => "n6", "source_port" => 0, "target" => "n7", "target_port" => 0},
      # All clear branch
      %{"id" => "e7", "source" => "n5", "source_port" => 1, "target" => "n8", "target_port" => 0}
    ]
  end
end
