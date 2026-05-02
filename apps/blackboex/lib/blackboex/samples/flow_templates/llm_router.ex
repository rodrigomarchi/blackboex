defmodule Blackboex.Samples.FlowTemplates.LlmRouter do
  @moduledoc """
  LLM Router / Model Dispatch template.

  Routes incoming prompts to different LLM API endpoints based on task type
  and budget tier. Demonstrates cost-optimized AI request routing — the #1
  n8n AI automation pattern in 2025. Uses httpbin.org to simulate LLM calls.

  ## Flow graph

      Start (prompt, task_type, budget_tier?)
        → Classify & Estimate (elixir_code — compute model_tier + token estimate)
        → Debug: Log Routing
        → Select Model (condition: 3-way)
          → Port 0 (high):     Prepare High → Call LLM → Extract → End (High Tier)
          → Port 1 (standard): Prepare Std  → Call LLM → Extract → End (Standard Tier)
          → Port 2 (low):      Prepare Low  → Call LLM → Extract → End (Low Tier)
  """

  @doc "Returns the LLM Router flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "llm_router",
      name: "LLM Router",
      description:
        "Routes prompts to different AI model tiers based on task type and budget — cost-optimized dispatch",
      category: "AI & LLM",
      icon: "hero-cpu-chip",
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
              "name" => "prompt",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "task_type",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "budget_tier",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "model_selected",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "model_tier",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "tokens_estimated",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "response",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "debug_routing",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => nil
            }
          ]
        }
      },

      # ── n2: Classify & Estimate ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 270, "y" => 250},
        "data" => %{
          "name" => "Classify & Estimate",
          "code" => ~S"""
          budget = input["budget_tier"] || "standard"
          task = input["task_type"]
          tokens = div(byte_size(input["prompt"]), 4) + 10

          tier =
            cond do
              budget == "high" or task == "analysis" -> "high"
              budget == "low" or task == "classification" -> "low"
              true -> "standard"
            end

          new_state =
            state
            |> Map.put("model_tier", tier)
            |> Map.put("tokens_estimated", tokens)

          {input, new_state}
          """
        }
      },

      # ── n3: Debug: Log Routing ──
      %{
        "id" => "n3",
        "type" => "debug",
        "position" => %{"x" => 490, "y" => 250},
        "data" => %{
          "name" => "Debug: Log Routing",
          "expression" =>
            ~S|%{"task" => input["task_type"], "budget" => input["budget_tier"], "tier" => state["model_tier"], "tokens" => state["tokens_estimated"]}|,
          "log_level" => "info",
          "state_key" => "debug_routing"
        }
      },

      # ── n4: Select Model (3-way condition) ──
      %{
        "id" => "n4",
        "type" => "condition",
        "position" => %{"x" => 710, "y" => 250},
        "data" => %{
          "name" => "Select Model",
          "expression" => ~S"""
          case state["model_tier"] do
            "high" -> 0
            "low" -> 2
            _ -> 1
          end
          """,
          "branch_labels" => %{
            "0" => "High Tier",
            "1" => "Standard",
            "2" => "Low Tier"
          }
        }
      },

      # ── n5: Prepare High-Tier Request ──
      %{
        "id" => "n5",
        "type" => "elixir_code",
        "position" => %{"x" => 960, "y" => 50},
        "data" => %{
          "name" => "Prepare High-Tier Request",
          "code" => ~S"""
          {input, Map.put(state, "model_selected", "claude-opus-4-6")}
          """
        }
      },

      # ── n6: Call High-Tier LLM ──
      %{
        "id" => "n6",
        "type" => "http_request",
        "position" => %{"x" => 1160, "y" => 50},
        "data" => %{
          "name" => "Call High-Tier LLM",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"model": "{{state.model_selected}}", "task": "{{input.task_type}}", "prompt": "{{input.prompt}}"}|,
          "timeout_ms" => 30_000,
          "max_retries" => 2,
          "expected_status" => [200]
        }
      },

      # ── n7: Extract Response (High) ──
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 1360, "y" => 50},
        "data" => %{
          "name" => "Extract Response (High)",
          "code" => ~S"""
          model = state["model_selected"]
          prompt = input["prompt"]
          response = "[#{model} high-tier response for: #{prompt}]"
          {input, Map.put(state, "response", response)}
          """
        }
      },

      # ── n8: End (High Tier) ──
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1560, "y" => 50},
        "data" => %{
          "name" => "End (High Tier)",
          "response_schema" => [
            %{
              "name" => "model_selected",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "model_tier",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "tokens_estimated",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "response", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "model_selected", "state_variable" => "model_selected"},
            %{"response_field" => "model_tier", "state_variable" => "model_tier"},
            %{"response_field" => "tokens_estimated", "state_variable" => "tokens_estimated"},
            %{"response_field" => "response", "state_variable" => "response"}
          ]
        }
      },

      # ── n9: Prepare Standard Request ──
      %{
        "id" => "n9",
        "type" => "elixir_code",
        "position" => %{"x" => 960, "y" => 250},
        "data" => %{
          "name" => "Prepare Standard Request",
          "code" => ~S"""
          {input, Map.put(state, "model_selected", "claude-sonnet-4-6")}
          """
        }
      },

      # ── n10: Call Standard LLM ──
      %{
        "id" => "n10",
        "type" => "http_request",
        "position" => %{"x" => 1160, "y" => 250},
        "data" => %{
          "name" => "Call Standard LLM",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"model": "{{state.model_selected}}", "task": "{{input.task_type}}", "prompt": "{{input.prompt}}"}|,
          "timeout_ms" => 20_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n11: Extract Response (Standard) ──
      %{
        "id" => "n11",
        "type" => "elixir_code",
        "position" => %{"x" => 1360, "y" => 250},
        "data" => %{
          "name" => "Extract Response (Standard)",
          "code" => ~S"""
          model = state["model_selected"]
          prompt = input["prompt"]
          response = "[#{model} standard response for: #{prompt}]"
          {input, Map.put(state, "response", response)}
          """
        }
      },

      # ── n12: End (Standard Tier) ──
      %{
        "id" => "n12",
        "type" => "end",
        "position" => %{"x" => 1560, "y" => 250},
        "data" => %{
          "name" => "End (Standard Tier)",
          "response_schema" => [
            %{
              "name" => "model_selected",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "model_tier",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "tokens_estimated",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "response", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "model_selected", "state_variable" => "model_selected"},
            %{"response_field" => "model_tier", "state_variable" => "model_tier"},
            %{"response_field" => "tokens_estimated", "state_variable" => "tokens_estimated"},
            %{"response_field" => "response", "state_variable" => "response"}
          ]
        }
      },

      # ── n13: Prepare Low-Tier Request ──
      %{
        "id" => "n13",
        "type" => "elixir_code",
        "position" => %{"x" => 960, "y" => 450},
        "data" => %{
          "name" => "Prepare Low-Tier Request",
          "code" => ~S"""
          {input, Map.put(state, "model_selected", "claude-haiku-4-5")}
          """
        }
      },

      # ── n14: Call Low-Tier LLM ──
      %{
        "id" => "n14",
        "type" => "http_request",
        "position" => %{"x" => 1160, "y" => 450},
        "data" => %{
          "name" => "Call Low-Tier LLM",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"model": "{{state.model_selected}}", "task": "{{input.task_type}}", "prompt": "{{input.prompt}}"}|,
          "timeout_ms" => 10_000,
          "max_retries" => 0,
          "expected_status" => [200]
        }
      },

      # ── n15: Extract Response (Low) ──
      %{
        "id" => "n15",
        "type" => "elixir_code",
        "position" => %{"x" => 1360, "y" => 450},
        "data" => %{
          "name" => "Extract Response (Low)",
          "code" => ~S"""
          model = state["model_selected"]
          prompt = input["prompt"]
          response = "[#{model} low-tier response for: #{prompt}]"
          {input, Map.put(state, "response", response)}
          """
        }
      },

      # ── n16: End (Low Tier) ──
      %{
        "id" => "n16",
        "type" => "end",
        "position" => %{"x" => 1560, "y" => 450},
        "data" => %{
          "name" => "End (Low Tier)",
          "response_schema" => [
            %{
              "name" => "model_selected",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "model_tier",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "tokens_estimated",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "response", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "model_selected", "state_variable" => "model_selected"},
            %{"response_field" => "model_tier", "state_variable" => "model_tier"},
            %{"response_field" => "tokens_estimated", "state_variable" => "tokens_estimated"},
            %{"response_field" => "response", "state_variable" => "response"}
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
      # High tier branch
      %{"id" => "e4", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0},
      %{"id" => "e5", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0},
      %{"id" => "e6", "source" => "n6", "source_port" => 0, "target" => "n7", "target_port" => 0},
      %{"id" => "e7", "source" => "n7", "source_port" => 0, "target" => "n8", "target_port" => 0},
      # Standard branch
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
      # Low tier branch
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
      %{
        "id" => "e15",
        "source" => "n15",
        "source_port" => 0,
        "target" => "n16",
        "target_port" => 0
      }
    ]
  end
end
