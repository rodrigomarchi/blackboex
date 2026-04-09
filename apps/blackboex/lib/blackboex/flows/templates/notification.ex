defmodule Blackboex.Flows.Templates.Notification do
  @moduledoc """
  Notification sub-flow template.

  A simple 3-node flow intended to be used as a sub-flow by other flows.
  Receives a message and channel, formats a notification string, and returns it.

  ## Flow graph

      Start (message, channel) → Format Notification → End (formatted message)
  """

  @doc "Returns the Notification sub-flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "notification",
      name: "Notification Sub-Flow",
      description:
        "A simple sub-flow that formats and returns a notification message via a given channel",
      category: "Getting Started",
      icon: "hero-bell",
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
      # ── Start ──
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 50, "y" => 200},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 10_000,
          "payload_schema" => [
            %{
              "name" => "message",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "channel",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            }
          ],
          "state_schema" => [
            %{
              "name" => "formatted",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            }
          ]
        }
      },

      # ── Format Notification ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 300, "y" => 200},
        "data" => %{
          "name" => "Format Notification",
          "code" => ~S"""
          channel = input["channel"]
          message = input["message"]
          formatted = "Notification via #{channel}: #{message}"
          {formatted, Map.put(state, "formatted", formatted)}
          """
        }
      },

      # ── End ──
      %{
        "id" => "n3",
        "type" => "end",
        "position" => %{"x" => 550, "y" => 200},
        "data" => %{
          "name" => "End",
          "response_schema" => [
            %{
              "name" => "formatted",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "formatted", "state_variable" => "formatted"}
          ]
        }
      }
    ]
  end

  defp edges do
    [
      # Start → Format Notification
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      # Format Notification → End
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0}
    ]
  end
end
