defmodule Blackboex.Flows.Templates.CustomerOnboarding do
  @moduledoc """
  Customer Onboarding template.

  Customer Success pipeline: provisions an account, sends a welcome message,
  waits a day, then branches on whether the customer has become active. Active
  customers complete; inactive customers receive a nudge.

  ## Flow graph

      Start → Provision → Welcome → Wait Day 1 → Check Activity → Is Active?
        → 0: Complete Onboarding → End (Active)
        → 1: Send Nudge          → End (Nudged)
  """

  @doc "Returns the Customer Onboarding flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "customer_onboarding",
      name: "Customer Onboarding",
      description: "Provisions, welcomes, and nudges new customers through a day-1 onboarding",
      category: "Customer Success",
      icon: "hero-user-plus",
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
              "name" => "customer_name",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "email",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "plan",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "already_active",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "account_provisioned",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "welcome_sent",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "is_active",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "onboarding_step",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "start"
            },
            %{
              "name" => "nudge_sent",
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
        "position" => %{"x" => 260, "y" => 250},
        "data" => %{
          "name" => "Provision Account",
          "code" => ~S"""
          new_state = state
            |> Map.put("account_provisioned", true)
            |> Map.put("onboarding_step", "provisioned")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 470, "y" => 250},
        "data" => %{
          "name" => "Send Welcome",
          "code" => ~S"""
          new_state = state
            |> Map.put("welcome_sent", true)
            |> Map.put("onboarding_step", "welcomed")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n4",
        "type" => "delay",
        "position" => %{"x" => 680, "y" => 250},
        "data" => %{
          "name" => "Wait Day 1",
          "duration_ms" => 10,
          "max_duration_ms" => 1_000
        }
      },
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 890, "y" => 250},
        "data" => %{
          "name" => "Check Activity",
          "code" => ~S"""
          is_active = input["already_active"] == true or input["plan"] == "enterprise"
          new_state = Map.put(state, "is_active", is_active)
          result = Map.put(input, "is_active", is_active)
          {result, new_state}
          """
        }
      },
      %{
        "id" => "n6",
        "type" => "condition",
        "position" => %{"x" => 1100, "y" => 250},
        "data" => %{
          "name" => "Is Active?",
          "expression" => ~S|if input["is_active"] == true, do: 0, else: 1|,
          "branch_labels" => %{
            "0" => "Active",
            "1" => "Inactive"
          }
        }
      },
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 1320, "y" => 100},
        "data" => %{
          "name" => "Complete Onboarding",
          "code" => ~S"""
          new_state = state
            |> Map.put("onboarding_step", "completed")
            |> Map.put("is_active", true)
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1540, "y" => 100},
        "data" => %{
          "name" => "End (Active)",
          "response_schema" => [
            %{
              "name" => "account_provisioned",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "welcome_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "is_active",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "onboarding_step",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{
              "response_field" => "account_provisioned",
              "state_variable" => "account_provisioned"
            },
            %{"response_field" => "welcome_sent", "state_variable" => "welcome_sent"},
            %{"response_field" => "is_active", "state_variable" => "is_active"},
            %{"response_field" => "onboarding_step", "state_variable" => "onboarding_step"}
          ]
        }
      },
      %{
        "id" => "n9",
        "type" => "elixir_code",
        "position" => %{"x" => 1320, "y" => 400},
        "data" => %{
          "name" => "Send Nudge",
          "code" => ~S"""
          new_state = state
            |> Map.put("nudge_sent", true)
            |> Map.put("onboarding_step", "nudged")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n10",
        "type" => "end",
        "position" => %{"x" => 1540, "y" => 400},
        "data" => %{
          "name" => "End (Nudged)",
          "response_schema" => [
            %{
              "name" => "account_provisioned",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "welcome_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "is_active",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "nudge_sent",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "onboarding_step",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{
              "response_field" => "account_provisioned",
              "state_variable" => "account_provisioned"
            },
            %{"response_field" => "welcome_sent", "state_variable" => "welcome_sent"},
            %{"response_field" => "is_active", "state_variable" => "is_active"},
            %{"response_field" => "nudge_sent", "state_variable" => "nudge_sent"},
            %{"response_field" => "onboarding_step", "state_variable" => "onboarding_step"}
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
      %{"id" => "e8", "source" => "n6", "source_port" => 1, "target" => "n9", "target_port" => 0},
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
