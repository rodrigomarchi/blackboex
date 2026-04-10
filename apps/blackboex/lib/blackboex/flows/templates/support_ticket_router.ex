defmodule Blackboex.Flows.Templates.SupportTicketRouter do
  @moduledoc """
  Support Ticket Router template.

  Classifies inbound support tickets by keyword, assigns a priority score based
  on urgency + category + body length, and routes them to critical / normal /
  backlog branches.

  ## Flow graph

      Start → Classify Ticket → Assign Priority → Route by Priority (3-way)
        → 0 (critical): Format Critical → End (Critical)
        → 1 (normal):   Format Normal   → End (Normal)
        → 2 (low):      Format Low      → End (Low)
  """

  @doc "Returns the Support Ticket Router flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "support_ticket_router",
      name: "Support Ticket Router",
      description: "Classifies and prioritises support tickets, routing them to the right team",
      category: "Customer Support",
      icon: "hero-ticket",
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
              "name" => "subject",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "body",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "sender_email",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "urgency",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "category",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "general"
            },
            %{
              "name" => "priority",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "normal"
            },
            %{
              "name" => "score",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "assigned_team",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "status",
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
        "position" => %{"x" => 260, "y" => 250},
        "data" => %{
          "name" => "Classify Ticket",
          "code" => ~S"""
          subject = String.downcase(input["subject"] || "")
          body = String.downcase(input["body"] || "")
          text = subject <> " " <> body

          category =
            cond do
              String.contains?(text, "bug") or String.contains?(text, "error") or String.contains?(text, "crash") ->
                "engineering"
              String.contains?(text, "billing") or String.contains?(text, "invoice") or String.contains?(text, "charge") ->
                "billing"
              String.contains?(text, "cancel") or String.contains?(text, "refund") ->
                "retention"
              true ->
                "general"
            end

          new_state = Map.put(state, "category", category)
          result = Map.put(input, "category", category)
          {result, new_state}
          """
        }
      },
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 470, "y" => 250},
        "data" => %{
          "name" => "Assign Priority",
          "code" => ~S"""
          category = state["category"] || "general"
          urgency = input["urgency"] || "normal"
          body_len = String.length(input["body"] || "")

          score = 0
          score = if urgency == "critical", do: score + 50, else: score
          score = if urgency == "normal", do: score + 10, else: score
          score = if category == "engineering", do: score + 20, else: score
          score = if category == "billing", do: score + 10, else: score
          score = if body_len > 200, do: score + 10, else: score

          priority =
            cond do
              score >= 50 -> "critical"
              score >= 20 -> "normal"
              true -> "low"
            end

          team =
            case category do
              "engineering" -> "eng-team"
              "billing" -> "billing-team"
              "retention" -> "retention-team"
              _ -> "general-support"
            end

          new_state = state
            |> Map.put("priority", priority)
            |> Map.put("score", score)
            |> Map.put("assigned_team", team)

          result = input
            |> Map.put("priority", priority)
            |> Map.put("score", score)
            |> Map.put("assigned_team", team)

          {result, new_state}
          """
        }
      },
      %{
        "id" => "n4",
        "type" => "condition",
        "position" => %{"x" => 680, "y" => 250},
        "data" => %{
          "name" => "Route by Priority",
          "expression" => ~S"""
          cond do
            input["priority"] == "critical" -> 0
            input["priority"] == "normal" -> 1
            true -> 2
          end
          """,
          "branch_labels" => %{
            "0" => "Critical",
            "1" => "Normal",
            "2" => "Low"
          }
        }
      },
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 80},
        "data" => %{
          "name" => "Format Critical",
          "code" => ~S"""
          new_state = Map.put(state, "status", "escalated")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n6",
        "type" => "end",
        "position" => %{"x" => 1120, "y" => 80},
        "data" => %{
          "name" => "End (Critical)",
          "response_schema" => [
            %{"name" => "category", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "priority", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "assigned_team",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "status", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "category", "state_variable" => "category"},
            %{"response_field" => "priority", "state_variable" => "priority"},
            %{"response_field" => "assigned_team", "state_variable" => "assigned_team"},
            %{"response_field" => "status", "state_variable" => "status"}
          ]
        }
      },
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 260},
        "data" => %{
          "name" => "Format Normal",
          "code" => ~S"""
          new_state = Map.put(state, "status", "queued")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1120, "y" => 260},
        "data" => %{
          "name" => "End (Normal)",
          "response_schema" => [
            %{"name" => "category", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "priority", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "status", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "category", "state_variable" => "category"},
            %{"response_field" => "priority", "state_variable" => "priority"},
            %{"response_field" => "status", "state_variable" => "status"}
          ]
        }
      },
      %{
        "id" => "n9",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 440},
        "data" => %{
          "name" => "Format Low",
          "code" => ~S"""
          new_state = Map.put(state, "status", "backlog")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n10",
        "type" => "end",
        "position" => %{"x" => 1120, "y" => 440},
        "data" => %{
          "name" => "End (Low)",
          "response_schema" => [
            %{"name" => "category", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "priority", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "status", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "category", "state_variable" => "category"},
            %{"response_field" => "priority", "state_variable" => "priority"},
            %{"response_field" => "status", "state_variable" => "status"}
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
      %{"id" => "e6", "source" => "n4", "source_port" => 1, "target" => "n7", "target_port" => 0},
      %{"id" => "e7", "source" => "n7", "source_port" => 0, "target" => "n8", "target_port" => 0},
      %{"id" => "e8", "source" => "n4", "source_port" => 2, "target" => "n9", "target_port" => 0},
      %{
        "id" => "e9",
        "source" => "n9",
        "source_port" => 0,
        "target" => "n10",
        "target_port" => 0
      }
    ]
  end
end
