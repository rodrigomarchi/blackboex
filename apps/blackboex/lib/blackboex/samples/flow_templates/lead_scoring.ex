defmodule Blackboex.Samples.FlowTemplates.LeadScoring do
  @moduledoc """
  Lead Scoring template — CRM lead qualification pipeline.

  Receives a lead (name, email, company, budget) and scores them for sales
  qualification. Demonstrates debug logging, skip conditions, and fail nodes.

  ## Flow graph

      Start → Debug: Log Lead → Score Lead (skippable) → Route by Score
        → Branch 0 (qualified): Enrich Lead → End Success
        → Branch 1 (unqualified): Fail
  """

  @doc "Returns the Lead Scoring flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "lead_scoring",
      name: "Lead Scoring",
      description:
        "CRM lead qualification with scoring, debug logging, and conditional rejection",
      category: "Advanced",
      icon: "hero-star",
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
      # ── Start ──
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
              "name" => "company",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "budget",
              "type" => "integer",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "skip_scoring",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "score",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "qualified",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "debug_lead",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => nil
            }
          ]
        }
      },

      # ── Debug: Log Lead ──
      %{
        "id" => "n2",
        "type" => "debug",
        "position" => %{"x" => 250, "y" => 250},
        "data" => %{
          "name" => "Log Lead",
          "expression" =>
            ~S|%{"name" => input["name"], "email" => input["email"], "company" => input["company"], "budget" => input["budget"]}|,
          "log_level" => "info",
          "state_key" => "debug_lead"
        }
      },

      # ── Score Lead (with skip_condition) ──
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 450, "y" => 250},
        "data" => %{
          "name" => "Score Lead",
          "skip_condition" => ~S|input["skip_scoring"] == true|,
          "code" => ~S"""
          score = 0
          score = if input["email"] != nil and input["email"] != "", do: score + 20, else: score
          score = if input["company"] != nil and input["company"] != "", do: score + 30, else: score
          score = if is_integer(input["budget"]) and input["budget"] > 1000, do: score + 50, else: score
          qualified = score >= 50

          result = %{"score" => score, "qualified" => qualified, "lead" => input}
          {result, Map.merge(state, %{"score" => score, "qualified" => qualified})}
          """
        }
      },

      # ── Route by Score ──
      %{
        "id" => "n4",
        "type" => "condition",
        "position" => %{"x" => 650, "y" => 250},
        "data" => %{
          "name" => "Route by Score",
          "expression" =>
            ~S|if input["qualified"] == true or input["qualified"] == nil, do: 0, else: 1|,
          "branch_labels" => %{"0" => "Qualified", "1" => "Not Qualified"}
        }
      },

      # ── Branch 0: Enrich Lead ──
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 150},
        "data" => %{
          "name" => "Enrich Lead",
          "code" => ~S"""
          lead = if is_map(input["lead"]), do: input["lead"], else: input
          result = %{
            "status" => "qualified",
            "name" => lead["name"],
            "email" => lead["email"],
            "company" => lead["company"],
            "score" => state["score"]
          }
          {result, Map.put(state, "enriched", true)}
          """
        }
      },

      # ── Branch 0: End Success ──
      %{
        "id" => "n6",
        "type" => "end",
        "position" => %{"x" => 1150, "y" => 150},
        "data" => %{"name" => "End Success"}
      },

      # ── Branch 1: Fail ──
      %{
        "id" => "n7",
        "type" => "fail",
        "position" => %{"x" => 900, "y" => 400},
        "data" => %{
          "name" => "Fail",
          "message" => ~S|"Lead not qualified: score #{state["score"]} is below threshold"|,
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
      %{"id" => "e5", "source" => "n4", "source_port" => 1, "target" => "n7", "target_port" => 0},
      %{"id" => "e6", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0}
    ]
  end
end
