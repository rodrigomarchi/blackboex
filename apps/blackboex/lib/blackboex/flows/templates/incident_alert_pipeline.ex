defmodule Blackboex.Flows.Templates.IncidentAlertPipeline do
  @moduledoc """
  Incident Alert Pipeline template.

  DevOps alert processing pipeline. Deduplicates duplicate alerts, classifies
  severity, and fans out to ticket / notify / log branches depending on
  severity level.

  ## Flow graph

      Start → Debug → Check Dedup → Is Duplicate?
        → 1: End (Skipped)
        → 0: Classify → Route by Severity
            → 0: Format Critical → Notify (http) → End (Critical)
            → 1: Format Warning → End (Warning)
            → 2: End (Info)
  """

  @doc "Returns the Incident Alert Pipeline flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "incident_alert_pipeline",
      name: "Incident Alert Pipeline",
      description:
        "Dedups, classifies and fans out monitoring alerts to ticket/notification branches",
      category: "DevOps & Monitoring",
      icon: "hero-bell-alert",
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
              "name" => "alert_name",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "severity",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "source",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "description",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "fingerprint",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "alert_id",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "severity_level",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "is_duplicate",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
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
              "name" => "debug_alert",
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
        "position" => %{"x" => 260, "y" => 300},
        "data" => %{
          "name" => "Log Alert",
          "expression" =>
            ~S|%{"alert_name" => input["alert_name"], "severity" => input["severity"], "source" => input["source"]}|,
          "log_level" => "info",
          "state_key" => "debug_alert"
        }
      },
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 470, "y" => 300},
        "data" => %{
          "name" => "Check Dedup",
          "code" => ~S"""
          fingerprint = input["fingerprint"] || ""
          alert_id =
            if fingerprint != "" do
              fingerprint
            else
              "alert_" <> (input["alert_name"] || "") <> "_" <> (input["source"] || "")
            end

          is_dup = String.starts_with?(fingerprint, "dup_")

          new_state = state
            |> Map.put("alert_id", alert_id)
            |> Map.put("is_duplicate", is_dup)

          result = Map.put(input, "is_duplicate", is_dup)
          {result, new_state}
          """
        }
      },
      %{
        "id" => "n4",
        "type" => "condition",
        "position" => %{"x" => 680, "y" => 300},
        "data" => %{
          "name" => "Is Duplicate?",
          "expression" => ~S|if input["is_duplicate"] == true, do: 1, else: 0|,
          "branch_labels" => %{
            "0" => "New",
            "1" => "Duplicate"
          }
        }
      },
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 200},
        "data" => %{
          "name" => "Classify",
          "code" => ~S"""
          severity = input["severity"] || "info"
          level =
            case severity do
              "critical" -> "critical"
              "warning" -> "warning"
              _ -> "info"
            end

          new_state = Map.put(state, "severity_level", level)
          result = Map.put(input, "severity_level", level)
          {result, new_state}
          """
        }
      },
      %{
        "id" => "n6",
        "type" => "condition",
        "position" => %{"x" => 1110, "y" => 200},
        "data" => %{
          "name" => "Route by Severity",
          "expression" => ~S"""
          cond do
            input["severity_level"] == "critical" -> 0
            input["severity_level"] == "warning" -> 1
            true -> 2
          end
          """,
          "branch_labels" => %{
            "0" => "Critical",
            "1" => "Warning",
            "2" => "Info"
          }
        }
      },
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 1330, "y" => 40},
        "data" => %{
          "name" => "Format Critical",
          "code" => ~S"""
          ticket_id = "tkt_" <> (state["alert_id"] || "unknown")
          new_state = state
            |> Map.put("ticket_id", ticket_id)
            |> Map.put("notification_sent", true)
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n8",
        "type" => "http_request",
        "position" => %{"x" => 1540, "y" => 40},
        "data" => %{
          "name" => "Notify",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"Content-Type" => "application/json"},
          "body_template" => ~S|{"alert": "{{state.alert_id}}", "ticket": "{{state.ticket_id}}"}|,
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1760, "y" => 40},
        "data" => %{
          "name" => "End (Critical)",
          "response_schema" => [
            %{"name" => "alert_id", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "severity_level",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "ticket_id",
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
            %{"response_field" => "alert_id", "state_variable" => "alert_id"},
            %{"response_field" => "severity_level", "state_variable" => "severity_level"},
            %{"response_field" => "ticket_id", "state_variable" => "ticket_id"},
            %{"response_field" => "notification_sent", "state_variable" => "notification_sent"}
          ]
        }
      },
      %{
        "id" => "n10",
        "type" => "elixir_code",
        "position" => %{"x" => 1330, "y" => 200},
        "data" => %{
          "name" => "Format Warning",
          "code" => ~S"""
          new_state = Map.put(state, "ticket_id", "warn_" <> (state["alert_id"] || ""))
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n11",
        "type" => "end",
        "position" => %{"x" => 1540, "y" => 200},
        "data" => %{
          "name" => "End (Warning)",
          "response_schema" => [
            %{"name" => "alert_id", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "severity_level",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "alert_id", "state_variable" => "alert_id"},
            %{"response_field" => "severity_level", "state_variable" => "severity_level"}
          ]
        }
      },
      %{
        "id" => "n12",
        "type" => "end",
        "position" => %{"x" => 1330, "y" => 360},
        "data" => %{
          "name" => "End (Info)",
          "response_schema" => [
            %{"name" => "alert_id", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "severity_level",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "alert_id", "state_variable" => "alert_id"},
            %{"response_field" => "severity_level", "state_variable" => "severity_level"}
          ]
        }
      },
      %{
        "id" => "n13",
        "type" => "end",
        "position" => %{"x" => 900, "y" => 480},
        "data" => %{
          "name" => "End (Skipped — Duplicate)",
          "response_schema" => [
            %{"name" => "alert_id", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "is_duplicate",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "alert_id", "state_variable" => "alert_id"},
            %{"response_field" => "is_duplicate", "state_variable" => "is_duplicate"}
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
        "source" => "n6",
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
      },
      %{
        "id" => "e11",
        "source" => "n6",
        "source_port" => 2,
        "target" => "n12",
        "target_port" => 0
      },
      %{
        "id" => "e12",
        "source" => "n4",
        "source_port" => 1,
        "target" => "n13",
        "target_port" => 0
      }
    ]
  end
end
