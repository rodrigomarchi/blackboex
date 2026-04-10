defmodule Blackboex.Flows.Templates.ApprovalWorkflow do
  @moduledoc """
  Approval Workflow template.

  A flow that conditionally halts for human approval via webhook_wait,
  then processes the result. Tests halt/resume lifecycle and conditional
  skipping of the wait step.

  ## Flow graph

      Start (request: string, amount: integer, auto_approve_below: integer)
        → Evaluate Request (elixir_code — check if auto-approve)
        → Needs Approval? (condition: 2-way)
          → Port 0: Wait for Approval (webhook_wait) → Process Approval (elixir_code) → End (Approved)
          → Port 1: Auto Approve (elixir_code) → End (Auto-Approved)
  """

  @doc "Returns the Approval Workflow flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "approval_workflow",
      name: "Approval Workflow",
      description:
        "Conditionally halts for human approval via webhook_wait — tests halt/resume lifecycle",
      category: "Advanced",
      icon: "hero-shield-check",
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
        "position" => %{"x" => 50, "y" => 250},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 30_000,
          "payload_schema" => [
            %{
              "name" => "request",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{"name" => "amount", "type" => "integer", "required" => true, "constraints" => %{}},
            %{
              "name" => "auto_approve_below",
              "type" => "integer",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "decision",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "pending"
            },
            %{
              "name" => "reason",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "approved_by",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            }
          ]
        }
      },

      # ── n2: Evaluate Request ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 280, "y" => 250},
        "data" => %{
          "name" => "Evaluate Request",
          "code" => ~S"""
          {input, state}
          """
        }
      },

      # ── n3: Needs Approval? ──
      %{
        "id" => "n3",
        "type" => "condition",
        "position" => %{"x" => 480, "y" => 250},
        "data" => %{
          "name" => "Needs Approval?",
          "expression" => ~S"""
          threshold = input["auto_approve_below"] || 0
          if input["amount"] >= threshold and threshold > 0, do: 0, else: 1
          """,
          "branch_labels" => %{
            "0" => "Needs Approval",
            "1" => "Auto Approve"
          }
        }
      },

      # ── n4: Wait for Approval (webhook_wait) ──
      %{
        "id" => "n4",
        "type" => "webhook_wait",
        "position" => %{"x" => 720, "y" => 100},
        "data" => %{
          "name" => "Wait for Approval",
          "event_type" => "approval_decision",
          "timeout_ms" => 3_600_000
        }
      },

      # ── n5: Process Approval ──
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 960, "y" => 100},
        "data" => %{
          "name" => "Process Approval",
          "code" => ~S"""
          decision = input["decision"] || "approved"
          reason = input["reason"] || ""
          approved_by = input["approved_by"] || "reviewer"

          new_state = state
            |> Map.put("decision", decision)
            |> Map.put("reason", reason)
            |> Map.put("approved_by", approved_by)

          {input, new_state}
          """
        }
      },

      # ── n6: End (Approved) ──
      %{
        "id" => "n6",
        "type" => "end",
        "position" => %{"x" => 1200, "y" => 100},
        "data" => %{
          "name" => "End (Approved)",
          "response_schema" => [
            %{"name" => "decision", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "reason", "type" => "string", "required" => false, "constraints" => %{}},
            %{
              "name" => "approved_by",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "decision", "state_variable" => "decision"},
            %{"response_field" => "reason", "state_variable" => "reason"},
            %{"response_field" => "approved_by", "state_variable" => "approved_by"}
          ]
        }
      },

      # ── n7: Auto Approve ──
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 720, "y" => 400},
        "data" => %{
          "name" => "Auto Approve",
          "code" => ~S"""
          new_state = state
            |> Map.put("decision", "auto_approved")
            |> Map.put("reason", "Amount #{input["amount"]} below threshold")
            |> Map.put("approved_by", "system")

          {input, new_state}
          """
        }
      },

      # ── n8: End (Auto-Approved) ──
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 960, "y" => 400},
        "data" => %{
          "name" => "End (Auto-Approved)",
          "response_schema" => [
            %{"name" => "decision", "type" => "string", "required" => true, "constraints" => %{}},
            %{"name" => "reason", "type" => "string", "required" => false, "constraints" => %{}},
            %{
              "name" => "approved_by",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "decision", "state_variable" => "decision"},
            %{"response_field" => "reason", "state_variable" => "reason"},
            %{"response_field" => "approved_by", "state_variable" => "approved_by"}
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
      %{"id" => "e6", "source" => "n3", "source_port" => 1, "target" => "n7", "target_port" => 0},
      %{"id" => "e7", "source" => "n7", "source_port" => 0, "target" => "n8", "target_port" => 0}
    ]
  end
end
