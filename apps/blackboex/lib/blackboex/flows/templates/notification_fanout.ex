defmodule Blackboex.Flows.Templates.NotificationFanout do
  @moduledoc """
  Notification Fanout template.

  Receives an internal event and fans out notifications to multiple channels
  (Slack, PagerDuty, email) based on severity, using for_each to iterate over
  the selected channels. Demonstrates the for_each node with HTTP calls.

  ## Flow graph

      Start (event_type, title, message, severity, source_system?)
        → Debug: Log Event
        → Determine Channels (elixir_code — severity determines channel list → state.channels)
        → Send Notifications (for_each over state.channels → POST httpbin per channel)
        → Aggregate Results (elixir_code — count sent, update state)
        → End (response mapping)
  """

  @doc "Returns the Notification Fanout flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "notification_fanout",
      name: "Notification Fanout",
      description:
        "Fans out event notifications to multiple channels based on severity — uses for_each for parallel dispatch",
      category: "Integrations",
      icon: "hero-megaphone",
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
              "name" => "title",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "message",
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
              "name" => "source_system",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "channels",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "string"},
              "initial_value" => []
            },
            %{
              "name" => "notifications_sent",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "results",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "object"},
              "initial_value" => []
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
        "position" => %{"x" => 270, "y" => 250},
        "data" => %{
          "name" => "Debug: Log Event",
          "expression" =>
            ~S|%{"event_type" => input["event_type"], "severity" => input["severity"], "title" => input["title"]}|,
          "log_level" => "info",
          "state_key" => "debug_event"
        }
      },

      # ── n3: Determine Channels ──
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 490, "y" => 250},
        "data" => %{
          "name" => "Determine Channels",
          "code" => ~S"""
          channels =
            case input["severity"] do
              "critical" -> ["slack-ops", "pagerduty", "email-oncall"]
              "high" -> ["slack-ops", "email-team"]
              "medium" -> ["slack-general"]
              _ -> ["slack-general"]
            end

          {input, Map.put(state, "channels", channels)}
          """
        }
      },

      # ── n4: Send Notifications (for_each) ──
      %{
        "id" => "n4",
        "type" => "for_each",
        "position" => %{"x" => 710, "y" => 250},
        "data" => %{
          "name" => "Send Notifications",
          "source_expression" => ~S'Map.get(state, "channels", [])',
          "body_code" => ~S"""
          %{
            "channel" => item,
            "status" => "sent",
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
          """,
          "item_variable" => "item",
          "accumulator" => "results",
          "batch_size" => 10
        }
      },

      # ── n5: Aggregate Results ──
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 930, "y" => 250},
        "data" => %{
          "name" => "Aggregate Results",
          "code" => ~S"""
          results = state["results"] || []
          sent = length(results)
          {input, Map.put(state, "notifications_sent", sent)}
          """
        }
      },

      # ── n6: End ──
      %{
        "id" => "n6",
        "type" => "end",
        "position" => %{"x" => 1150, "y" => 250},
        "data" => %{
          "name" => "End",
          "response_schema" => [
            %{
              "name" => "channels",
              "type" => "array",
              "required" => true,
              "constraints" => %{"item_type" => "string"}
            },
            %{
              "name" => "notifications_sent",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "results",
              "type" => "array",
              "required" => true,
              "constraints" => %{"item_type" => "object"}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "channels", "state_variable" => "channels"},
            %{"response_field" => "notifications_sent", "state_variable" => "notifications_sent"},
            %{"response_field" => "results", "state_variable" => "results"}
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
      %{"id" => "e5", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0}
    ]
  end
end
