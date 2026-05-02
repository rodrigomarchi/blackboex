defmodule Blackboex.Samples.FlowTemplates.ApprovalWithTimeout do
  @moduledoc """
  Human Approval with Timeout + Reminder template.

  Sends an approval request, waits for a human response via webhook_wait.
  If no response, sends a reminder and waits again. If still no response,
  auto-escalates. Demonstrates the "Human in the Loop with Timeout" pattern
  — Temporal's canonical durable workflow example.

  ## Flow graph

      Start (request_title, requester, amount, approver_email, simulate_timeout?)
        → Prepare Request (elixir_code)
        → Send Approval Request (http_request → httpbin)
        → Skip Wait? (condition: test bypass via simulate_timeout)
          → Port 0 (normal):
              Wait for Decision (webhook_wait, 60 min)
              → Decision Received? (condition)
                → Port 0: Process Decision → End (Decided)
                → Port 1: Send Reminder → Send Reminder Notification
                    → Wait After Reminder (webhook_wait, 30 min)
                    → Decision After Reminder? (condition)
                      → Port 0: Process Final Decision → End (Decided After Reminder)
                      → Port 1: Auto-Escalate → End (Escalated)
          → Port 1 (test): Process Timeout → End (Test Timeout)
  """

  @doc "Returns the Human Approval with Timeout flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "approval_with_timeout",
      name: "Human Approval with Timeout + Reminder",
      description:
        "Halts for human approval, sends a reminder after timeout, auto-escalates if still no response",
      category: "Business Operations",
      icon: "hero-clock",
      definition: definition()
    }
  end

  @doc false
  @spec definition() :: map()
  def definition do
    %{"version" => "1.0", "nodes" => nodes(), "edges" => edges()}
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
          "timeout" => 30_000,
          "payload_schema" => [
            %{
              "name" => "request_title",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "requester",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "amount", "type" => "integer", "required" => true, "constraints" => %{}},
            %{
              "name" => "approver_email",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "simulate_timeout",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "simulate_timeout",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "decision",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "pending"
            },
            %{
              "name" => "reminder_sent",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "escalated",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "approved_by",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "request_url",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            }
          ]
        }
      },

      # ── n2: Prepare Request ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 270, "y" => 300},
        "data" => %{
          "name" => "Prepare Request",
          "code" => ~S"""
          token = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
          request_url = "https://app.example.com/approvals/#{token}"

          new_state =
            state
            |> Map.put("request_url", request_url)
            |> Map.put("simulate_timeout", input["simulate_timeout"] == true)

          {input, new_state}
          """
        }
      },

      # ── n3: Send Approval Request ──
      %{
        "id" => "n3",
        "type" => "http_request",
        "position" => %{"x" => 490, "y" => 300},
        "data" => %{
          "name" => "Send Approval Request",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"to": "{{input.approver_email}}", "subject": "Approval Required: {{input.request_title}}", "requester": "{{input.requester}}", "amount": {{input.amount}}, "approve_url": "{{state.request_url}}"}|,
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n4: Skip Wait (Test Mode)? ──
      %{
        "id" => "n4",
        "type" => "condition",
        "position" => %{"x" => 710, "y" => 300},
        "data" => %{
          "name" => "Skip Wait (Test Mode)?",
          "expression" => ~S"""
          if state["simulate_timeout"] == true, do: 1, else: 0
          """,
          "branch_labels" => %{"0" => "Normal Flow", "1" => "Simulate Timeout"}
        }
      },

      # ── n5: Wait for Decision (Primary) ──
      %{
        "id" => "n5",
        "type" => "webhook_wait",
        "position" => %{"x" => 930, "y" => 150},
        "data" => %{
          "name" => "Wait for Decision (Primary)",
          "event_type" => "approval_response",
          "timeout_ms" => 3_600_000
        }
      },

      # ── n6: Decision Received? ──
      %{
        "id" => "n6",
        "type" => "condition",
        "position" => %{"x" => 1150, "y" => 150},
        "data" => %{
          "name" => "Decision Received?",
          "expression" => ~S"""
          if input["approved"] != nil, do: 0, else: 1
          """,
          "branch_labels" => %{"0" => "Approved/Rejected", "1" => "Timed Out"}
        }
      },

      # ── n7: Process Decision ──
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 1370, "y" => 50},
        "data" => %{
          "name" => "Process Decision",
          "code" => ~S"""
          decision = if input["approved"] == true, do: "approved", else: "rejected"
          approved_by = input["approver"] || input["approver_email"] || "unknown"

          new_state =
            state
            |> Map.put("decision", decision)
            |> Map.put("approved_by", approved_by)

          {input, new_state}
          """
        }
      },

      # ── n8: End (Decided) ──
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1570, "y" => 50},
        "data" => %{
          "name" => "End (Decided)",
          "response_schema" => [
            %{"name" => "decision", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "approved_by",
              "type" => "string",
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
              "name" => "escalated",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "decision", "state_variable" => "decision"},
            %{"response_field" => "approved_by", "state_variable" => "approved_by"},
            %{"response_field" => "reminder_sent", "state_variable" => "reminder_sent"},
            %{"response_field" => "escalated", "state_variable" => "escalated"}
          ]
        }
      },

      # ── n9: Send Reminder ──
      %{
        "id" => "n9",
        "type" => "elixir_code",
        "position" => %{"x" => 1370, "y" => 200},
        "data" => %{
          "name" => "Send Reminder",
          "code" => ~S"""
          {input, Map.put(state, "reminder_sent", true)}
          """
        }
      },

      # ── n10: Send Reminder Notification ──
      %{
        "id" => "n10",
        "type" => "http_request",
        "position" => %{"x" => 1570, "y" => 200},
        "data" => %{
          "name" => "Send Reminder Notification",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"to": "{{input.approver_email}}", "subject": "REMINDER: {{input.request_title}} needs your approval", "reminder": true}|,
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n11: Wait for Decision (After Reminder) ──
      %{
        "id" => "n11",
        "type" => "webhook_wait",
        "position" => %{"x" => 1770, "y" => 200},
        "data" => %{
          "name" => "Wait for Decision (After Reminder)",
          "event_type" => "approval_response",
          "timeout_ms" => 1_800_000
        }
      },

      # ── n12: Decision After Reminder? ──
      %{
        "id" => "n12",
        "type" => "condition",
        "position" => %{"x" => 1970, "y" => 200},
        "data" => %{
          "name" => "Decision After Reminder?",
          "expression" => ~S"""
          if input["approved"] != nil, do: 0, else: 1
          """,
          "branch_labels" => %{"0" => "Approved/Rejected", "1" => "Still No Response"}
        }
      },

      # ── n13: Process Final Decision ──
      %{
        "id" => "n13",
        "type" => "elixir_code",
        "position" => %{"x" => 2170, "y" => 150},
        "data" => %{
          "name" => "Process Final Decision",
          "code" => ~S"""
          decision = if input["approved"] == true, do: "approved", else: "rejected"
          approved_by = input["approver"] || input["approver_email"] || "unknown"

          new_state =
            state
            |> Map.put("decision", decision)
            |> Map.put("approved_by", approved_by)

          {input, new_state}
          """
        }
      },

      # ── n14: End (Decided After Reminder) ──
      %{
        "id" => "n14",
        "type" => "end",
        "position" => %{"x" => 2370, "y" => 150},
        "data" => %{
          "name" => "End (Decided After Reminder)",
          "response_schema" => [
            %{"name" => "decision", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "approved_by",
              "type" => "string",
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
              "name" => "escalated",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "decision", "state_variable" => "decision"},
            %{"response_field" => "approved_by", "state_variable" => "approved_by"},
            %{"response_field" => "reminder_sent", "state_variable" => "reminder_sent"},
            %{"response_field" => "escalated", "state_variable" => "escalated"}
          ]
        }
      },

      # ── n15: Auto-Escalate ──
      %{
        "id" => "n15",
        "type" => "elixir_code",
        "position" => %{"x" => 2170, "y" => 300},
        "data" => %{
          "name" => "Auto-Escalate",
          "code" => ~S"""
          new_state =
            state
            |> Map.put("decision", "escalated")
            |> Map.put("escalated", true)

          {input, new_state}
          """
        }
      },

      # ── n16: End (Escalated) ──
      %{
        "id" => "n16",
        "type" => "end",
        "position" => %{"x" => 2370, "y" => 300},
        "data" => %{
          "name" => "End (Escalated)",
          "response_schema" => [
            %{"name" => "decision", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "escalated",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "reminder_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "decision", "state_variable" => "decision"},
            %{"response_field" => "escalated", "state_variable" => "escalated"},
            %{"response_field" => "reminder_sent", "state_variable" => "reminder_sent"}
          ]
        }
      },

      # ── n17: Process Timeout (Test) ──
      %{
        "id" => "n17",
        "type" => "elixir_code",
        "position" => %{"x" => 930, "y" => 450},
        "data" => %{
          "name" => "Process Timeout (Test)",
          "code" => ~S"""
          new_state =
            state
            |> Map.put("decision", "escalated")
            |> Map.put("escalated", true)

          {input, new_state}
          """
        }
      },

      # ── n18: End (Test Timeout) ──
      %{
        "id" => "n18",
        "type" => "end",
        "position" => %{"x" => 1150, "y" => 450},
        "data" => %{
          "name" => "End (Test Timeout)",
          "response_schema" => [
            %{"name" => "decision", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "escalated",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "reminder_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "decision", "state_variable" => "decision"},
            %{"response_field" => "escalated", "state_variable" => "escalated"},
            %{"response_field" => "reminder_sent", "state_variable" => "reminder_sent"}
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
      # Normal path → webhook_wait
      %{"id" => "e4", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0},
      %{"id" => "e5", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0},
      # Decision received → process
      %{"id" => "e6", "source" => "n6", "source_port" => 0, "target" => "n7", "target_port" => 0},
      %{"id" => "e7", "source" => "n7", "source_port" => 0, "target" => "n8", "target_port" => 0},
      # Timed out → reminder
      %{"id" => "e8", "source" => "n6", "source_port" => 1, "target" => "n9", "target_port" => 0},
      %{
        "id" => "e9",
        "source" => "n9",
        "source_port" => 0,
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
        "source" => "n11",
        "source_port" => 0,
        "target" => "n12",
        "target_port" => 0
      },
      # After reminder: decision received
      %{
        "id" => "e12",
        "source" => "n12",
        "source_port" => 0,
        "target" => "n13",
        "target_port" => 0
      },
      %{
        "id" => "e13",
        "source" => "n13",
        "source_port" => 0,
        "target" => "n14",
        "target_port" => 0
      },
      # After reminder: still no response → escalate
      %{
        "id" => "e14",
        "source" => "n12",
        "source_port" => 1,
        "target" => "n15",
        "target_port" => 0
      },
      %{
        "id" => "e15",
        "source" => "n15",
        "source_port" => 0,
        "target" => "n16",
        "target_port" => 0
      },
      # Test bypass → simulate timeout
      %{
        "id" => "e16",
        "source" => "n4",
        "source_port" => 1,
        "target" => "n17",
        "target_port" => 0
      },
      %{
        "id" => "e17",
        "source" => "n17",
        "source_port" => 0,
        "target" => "n18",
        "target_port" => 0
      }
    ]
  end
end
