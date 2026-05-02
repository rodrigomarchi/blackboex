defmodule Blackboex.Samples.FlowTemplates.EscalationApproval do
  @moduledoc """
  Escalation Approval template.

  Business operations approval flow. If the requested amount falls below a
  configured auto-approve threshold the flow is auto-approved immediately;
  otherwise it halts on a `webhook_wait` node until a reviewer posts an
  approval_decision event.

  ## Flow graph

      Start → Prepare Request → Check Auto-Approve (2-way)
        → 0 (needs approval): Wait → Process Decision (2-way)
             → 0: Approved → End (Approved)
             → 1: Rejected → End (Rejected)
        → 1 (auto): Auto Approve → End (Auto-Approved)
  """

  @doc "Returns the Escalation Approval flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "escalation_approval",
      name: "Escalation Approval",
      description: "Auto-approves small requests and halts larger ones until a reviewer decides",
      category: "Business Operations",
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
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 50, "y" => 300},
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
            %{
              "name" => "amount",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "requester",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
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
            },
            %{
              "name" => "escalation_level",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "auto_approved",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            }
          ]
        }
      },
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 260, "y" => 300},
        "data" => %{
          "name" => "Prepare Request",
          "code" => ~S"""
          new_state = Map.put(state, "escalation_level", 1)
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n3",
        "type" => "condition",
        "position" => %{"x" => 470, "y" => 300},
        "data" => %{
          "name" => "Check Auto-Approve",
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
      %{
        "id" => "n4",
        "type" => "webhook_wait",
        "position" => %{"x" => 700, "y" => 120},
        "data" => %{
          "name" => "Wait for Approval",
          "event_type" => "approval_decision",
          "timeout_ms" => 3_600_000
        }
      },
      %{
        "id" => "n5",
        "type" => "condition",
        "position" => %{"x" => 920, "y" => 120},
        "data" => %{
          "name" => "Process Decision",
          "expression" => ~S|if input["decision"] == "approved", do: 0, else: 1|,
          "branch_labels" => %{
            "0" => "Approved",
            "1" => "Rejected"
          }
        }
      },
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 1140, "y" => 40},
        "data" => %{
          "name" => "Approved",
          "code" => ~S"""
          new_state = state
            |> Map.put("decision", "approved")
            |> Map.put("reason", input["reason"] || "Approved by reviewer")
            |> Map.put("approved_by", input["approved_by"] || "reviewer")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n7",
        "type" => "end",
        "position" => %{"x" => 1360, "y" => 40},
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
            },
            %{
              "name" => "escalation_level",
              "type" => "integer",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "decision", "state_variable" => "decision"},
            %{"response_field" => "reason", "state_variable" => "reason"},
            %{"response_field" => "approved_by", "state_variable" => "approved_by"},
            %{"response_field" => "escalation_level", "state_variable" => "escalation_level"}
          ]
        }
      },
      %{
        "id" => "n8",
        "type" => "elixir_code",
        "position" => %{"x" => 1140, "y" => 220},
        "data" => %{
          "name" => "Rejected",
          "code" => ~S"""
          new_state = state
            |> Map.put("decision", "rejected")
            |> Map.put("reason", input["reason"] || "Rejected by reviewer")
            |> Map.put("approved_by", input["approved_by"] || "reviewer")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1360, "y" => 220},
        "data" => %{
          "name" => "End (Rejected)",
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
      %{
        "id" => "n10",
        "type" => "elixir_code",
        "position" => %{"x" => 700, "y" => 480},
        "data" => %{
          "name" => "Auto Approve",
          "code" => ~S"""
          new_state = state
            |> Map.put("decision", "auto_approved")
            |> Map.put("auto_approved", true)
            |> Map.put("approved_by", "system")
            |> Map.put("reason", "Amount #{input["amount"]} below auto-approve threshold")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n11",
        "type" => "end",
        "position" => %{"x" => 920, "y" => 480},
        "data" => %{
          "name" => "End (Auto-Approved)",
          "response_schema" => [
            %{"name" => "decision", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "auto_approved",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "approved_by",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{"name" => "reason", "type" => "string", "required" => false, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "decision", "state_variable" => "decision"},
            %{"response_field" => "auto_approved", "state_variable" => "auto_approved"},
            %{"response_field" => "approved_by", "state_variable" => "approved_by"},
            %{"response_field" => "reason", "state_variable" => "reason"}
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
      %{"id" => "e7", "source" => "n5", "source_port" => 1, "target" => "n8", "target_port" => 0},
      %{"id" => "e8", "source" => "n8", "source_port" => 0, "target" => "n9", "target_port" => 0},
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
