defmodule Blackboex.Samples.FlowTemplates.AdvancedFeatures do
  @moduledoc """
  Advanced Features template — Data Validation Pipeline.

  Demonstrates the new flow engine capabilities:
  - Debug node for input inspection
  - Skip condition on validation node
  - Fail node for explicit error signaling
  - Branching with condition

  ## Flow graph

      Start → Debug (log input) → Validate (skippable) → Route
        → Branch 0: Transform → End (Success)
        → Branch 1: Fail (validation error)
  """

  @doc "Returns the Advanced Features flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "advanced_features",
      name: "Advanced Features",
      description: "Data validation pipeline demonstrating debug, skip condition, and fail nodes",
      category: "Advanced",
      icon: "hero-beaker",
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
              "name" => "strict_mode",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "skip_validation",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "validated",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "debug_input",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => nil
            }
          ]
        }
      },

      # ── Debug: Log Input ──
      %{
        "id" => "n2",
        "type" => "debug",
        "position" => %{"x" => 250, "y" => 250},
        "data" => %{
          "name" => "Log Input",
          "expression" =>
            ~S|%{"name" => input["name"], "email" => input["email"], "strict" => input["strict_mode"]}|,
          "log_level" => "info",
          "state_key" => "debug_input"
        }
      },

      # ── Validate Data (with skip_condition) ──
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 450, "y" => 250},
        "data" => %{
          "name" => "Validate Data",
          "skip_condition" => ~S|input["skip_validation"] == true|,
          "code" => ~S"""
          name = input["name"]
          email = input["email"]
          strict = input["strict_mode"]

          errors = []
          errors = if is_nil(name) or name == "", do: ["name is required" | errors], else: errors
          errors = if strict == true and (is_nil(email) or email == ""), do: ["email required in strict mode" | errors], else: errors

          valid? = errors == []

          result = %{
            "valid" => valid?,
            "errors" => Enum.reverse(errors),
            "data" => input
          }

          {result, Map.put(state, "validated", valid?)}
          """
        }
      },

      # ── Route by Validity ──
      %{
        "id" => "n4",
        "type" => "condition",
        "position" => %{"x" => 650, "y" => 250},
        "data" => %{
          "name" => "Route by Validity",
          "expression" => ~S|if input["valid"] == true or input["valid"] == nil, do: 0, else: 1|,
          "branch_labels" => %{"0" => "Valid", "1" => "Invalid"}
        }
      },

      # ── Branch 0: Transform Data ──
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 900, "y" => 150},
        "data" => %{
          "name" => "Transform Data",
          "code" => ~S"""
          data = if is_map(input["data"]), do: input["data"], else: input
          name = data["name"] || ""

          result = %{
            "greeting" => "Hello, #{String.upcase(name)}!",
            "processed" => true,
            "email" => data["email"]
          }

          {result, Map.put(state, "transformed", true)}
          """
        }
      },

      # ── Branch 0: End (Success) ──
      %{
        "id" => "n6",
        "type" => "end",
        "position" => %{"x" => 1150, "y" => 150},
        "data" => %{"name" => "End (Success)"}
      },

      # ── Branch 1: Fail ──
      %{
        "id" => "n7",
        "type" => "fail",
        "position" => %{"x" => 900, "y" => 400},
        "data" => %{
          "name" => "Validation Failed",
          "message" => ~S|"Validation failed: #{Enum.join(input["errors"], ", ")}"|,
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
