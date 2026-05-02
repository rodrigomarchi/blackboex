defmodule Blackboex.Samples.FlowTemplates.GithubCiResponder do
  @moduledoc """
  GitHub CI/CD Event Responder template.

  Listens to CI/CD webhook events (build_failed, pr_merged, deployment_success,
  pr_opened) and routes them to appropriate actions: creates a ticket for
  failures, notifies Slack for merges, triggers downstream deploys for
  successes, and acknowledges PR opens. Uses httpbin.org to simulate API calls.

  ## Flow graph

      Start (event_type, repository, branch, actor, ...)
        → Debug: Log CI Event
        → Validate Event (elixir_code)
        → Route CI Event (condition: 4-way)
          → Port 0 (build_failed):       Prepare Ticket → Create Ticket API → Record Failure → End (Build Failed)
          → Port 1 (pr_merged):          Format Merge → Notify Slack → Record Merge → End (PR Merged)
          → Port 2 (deployment_success): Prepare Deploy → Trigger Deploy → End (Deployment Success)
          → Port 3 (pr_opened):          Acknowledge PR → End (PR Opened)
  """

  @doc "Returns the GitHub CI Responder flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "github_ci_responder",
      name: "GitHub CI Responder",
      description:
        "Routes CI/CD webhook events to ticket creation, Slack notifications, or deploy triggers",
      category: "DevOps & Monitoring",
      icon: "hero-code-bracket",
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
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "repository",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "branch",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "actor",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "commit_sha",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "build_url",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "pr_number",
              "type" => "integer",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "action_taken",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "ticket_id",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "notification_sent",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "deploy_triggered",
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

      # ── n2: Debug: Log CI Event ──
      %{
        "id" => "n2",
        "type" => "debug",
        "position" => %{"x" => 270, "y" => 250},
        "data" => %{
          "name" => "Debug: Log CI Event",
          "expression" =>
            ~S|%{"event" => input["event_type"], "repo" => input["repository"], "branch" => input["branch"], "actor" => input["actor"]}|,
          "log_level" => "info",
          "state_key" => "debug_event"
        }
      },

      # ── n3: Validate Event ──
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 490, "y" => 250},
        "data" => %{
          "name" => "Validate Event",
          "code" => ~S"""
          summary = "#{input["event_type"]} on #{input["repository"]}@#{input["branch"]} by #{input["actor"]}"
          result = Map.put(input, "summary", summary)
          {result, state}
          """
        }
      },

      # ── n4: Route CI Event (4-way condition) ──
      %{
        "id" => "n4",
        "type" => "condition",
        "position" => %{"x" => 710, "y" => 250},
        "data" => %{
          "name" => "Route CI Event",
          "expression" => ~S"""
          case input["event_type"] do
            "build_failed" -> 0
            "pr_merged" -> 1
            "deployment_success" -> 2
            _ -> 3
          end
          """,
          "branch_labels" => %{
            "0" => "Build Failed",
            "1" => "PR Merged",
            "2" => "Deployment",
            "3" => "PR Opened"
          }
        }
      },

      # ── n5: Prepare Failure Ticket ──
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 960, "y" => 50},
        "data" => %{
          "name" => "Prepare Failure Ticket",
          "code" => ~S"""
          ticket_id = "BUG-" <> (Ecto.UUID.generate() |> String.slice(0, 8))
          new_state = Map.put(state, "ticket_id", ticket_id)
          {input, new_state}
          """
        }
      },

      # ── n6: Create Failure Ticket ──
      %{
        "id" => "n6",
        "type" => "http_request",
        "position" => %{"x" => 1160, "y" => 50},
        "data" => %{
          "name" => "Create Failure Ticket",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"ticket_id": "{{state.ticket_id}}", "title": "Build failed: {{input.repository}}@{{input.branch}}", "build_url": "{{input.build_url}}"}|,
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n7: Record Failure ──
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 1360, "y" => 50},
        "data" => %{
          "name" => "Record Failure",
          "code" => ~S"""
          new_state =
            state
            |> Map.put("action_taken", "ticket_created")
            |> Map.put("notification_sent", true)
          {input, new_state}
          """
        }
      },

      # ── n8: End (Build Failed) ──
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1560, "y" => 50},
        "data" => %{
          "name" => "End (Build Failed)",
          "response_schema" => [
            %{
              "name" => "action_taken",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "ticket_id",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "notification_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "action_taken", "state_variable" => "action_taken"},
            %{"response_field" => "ticket_id", "state_variable" => "ticket_id"},
            %{"response_field" => "notification_sent", "state_variable" => "notification_sent"}
          ]
        }
      },

      # ── n9: Format Merge Notification ──
      %{
        "id" => "n9",
        "type" => "elixir_code",
        "position" => %{"x" => 960, "y" => 200},
        "data" => %{
          "name" => "Format Merge Notification",
          "code" => ~S"""
          new_state = Map.put(state, "action_taken", "merge_notified")
          {input, new_state}
          """
        }
      },

      # ── n10: Notify Merge to Slack ──
      %{
        "id" => "n10",
        "type" => "http_request",
        "position" => %{"x" => 1160, "y" => 200},
        "data" => %{
          "name" => "Notify Merge to Slack",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"channel": "#deploys", "text": "PR #{{input.pr_number}} merged into {{input.repository}}@{{input.branch}} by {{input.actor}}"}|,
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n11: Record Merge ──
      %{
        "id" => "n11",
        "type" => "elixir_code",
        "position" => %{"x" => 1360, "y" => 200},
        "data" => %{
          "name" => "Record Merge",
          "code" => ~S"""
          {input, Map.put(state, "notification_sent", true)}
          """
        }
      },

      # ── n12: End (PR Merged) ──
      %{
        "id" => "n12",
        "type" => "end",
        "position" => %{"x" => 1560, "y" => 200},
        "data" => %{
          "name" => "End (PR Merged)",
          "response_schema" => [
            %{
              "name" => "action_taken",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "notification_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "action_taken", "state_variable" => "action_taken"},
            %{"response_field" => "notification_sent", "state_variable" => "notification_sent"}
          ]
        }
      },

      # ── n13: Prepare Deploy Trigger ──
      %{
        "id" => "n13",
        "type" => "elixir_code",
        "position" => %{"x" => 960, "y" => 350},
        "data" => %{
          "name" => "Prepare Deploy Trigger",
          "code" => ~S"""
          new_state =
            state
            |> Map.put("action_taken", "deploy_triggered")
            |> Map.put("deploy_triggered", true)
          {input, new_state}
          """
        }
      },

      # ── n14: Trigger Downstream Deploy ──
      %{
        "id" => "n14",
        "type" => "http_request",
        "position" => %{"x" => 1160, "y" => 350},
        "data" => %{
          "name" => "Trigger Downstream Deploy",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"trigger": "deploy", "repository": "{{input.repository}}", "branch": "{{input.branch}}", "sha": "{{input.commit_sha}}"}|,
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n15: End (Deployment Success) ──
      %{
        "id" => "n15",
        "type" => "end",
        "position" => %{"x" => 1360, "y" => 350},
        "data" => %{
          "name" => "End (Deployment Success)",
          "response_schema" => [
            %{
              "name" => "action_taken",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "deploy_triggered",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "action_taken", "state_variable" => "action_taken"},
            %{"response_field" => "deploy_triggered", "state_variable" => "deploy_triggered"}
          ]
        }
      },

      # ── n16: Acknowledge PR ──
      %{
        "id" => "n16",
        "type" => "elixir_code",
        "position" => %{"x" => 960, "y" => 500},
        "data" => %{
          "name" => "Acknowledge PR",
          "code" => ~S"""
          new_state =
            state
            |> Map.put("action_taken", "pr_acknowledged")
            |> Map.put("notification_sent", true)
          {input, new_state}
          """
        }
      },

      # ── n17: End (PR Opened) ──
      %{
        "id" => "n17",
        "type" => "end",
        "position" => %{"x" => 1160, "y" => 500},
        "data" => %{
          "name" => "End (PR Opened)",
          "response_schema" => [
            %{
              "name" => "action_taken",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "notification_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "action_taken", "state_variable" => "action_taken"},
            %{"response_field" => "notification_sent", "state_variable" => "notification_sent"}
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
      # Build failed branch
      %{"id" => "e4", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0},
      %{"id" => "e5", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0},
      %{"id" => "e6", "source" => "n6", "source_port" => 0, "target" => "n7", "target_port" => 0},
      %{"id" => "e7", "source" => "n7", "source_port" => 0, "target" => "n8", "target_port" => 0},
      # PR merged branch
      %{"id" => "e8", "source" => "n4", "source_port" => 1, "target" => "n9", "target_port" => 0},
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
      # Deployment success branch
      %{
        "id" => "e12",
        "source" => "n4",
        "source_port" => 2,
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
      %{
        "id" => "e14",
        "source" => "n14",
        "source_port" => 0,
        "target" => "n15",
        "target_port" => 0
      },
      # PR opened branch
      %{
        "id" => "e15",
        "source" => "n4",
        "source_port" => 3,
        "target" => "n16",
        "target_port" => 0
      },
      %{
        "id" => "e16",
        "source" => "n16",
        "source_port" => 0,
        "target" => "n17",
        "target_port" => 0
      }
    ]
  end
end
