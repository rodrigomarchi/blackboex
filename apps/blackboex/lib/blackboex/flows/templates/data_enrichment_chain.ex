defmodule Blackboex.Flows.Templates.DataEnrichmentChain do
  @moduledoc """
  Data Enrichment Chain template.

  Tries a primary enrichment source (HTTP call), and on "miss" falls back to a
  secondary source. Because BlackboexFlow does not support fan-in, each branch
  owns its own merge and end node.

  ## Flow graph

      Start → Prepare Query → Fetch Primary (http_request) → Check Primary
        → Source 1 Found? (2-way)
          → 0: Extract Primary  → Merge Primary  → End (Primary)
          → 1: Fetch Fallback (http_request) → Check Fallback
                → Extract Fallback → Merge Fallback → End (Fallback)
  """

  @doc "Returns the Data Enrichment Chain flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "data_enrichment_chain",
      name: "Data Enrichment Chain",
      description: "Enriches records by chaining primary and fallback HTTP data sources",
      category: "Data & Enrichment",
      icon: "hero-circle-stack",
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
              "name" => "email",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{"name" => "name", "type" => "string", "required" => false, "constraints" => %{}},
            %{"name" => "company", "type" => "string", "required" => false, "constraints" => %{}}
          ],
          "state_schema" => [
            %{
              "name" => "source",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "none"
            },
            %{
              "name" => "confidence",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "enriched_name",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "enriched_company",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "sources_tried",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "query",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            }
          ]
        }
      },
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 260, "y" => 250},
        "data" => %{
          "name" => "Prepare Query",
          "code" => ~S"""
          new_state = Map.put(state, "query", input["email"] || "")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n3",
        "type" => "http_request",
        "position" => %{"x" => 470, "y" => 250},
        "data" => %{
          "name" => "Fetch Primary",
          "method" => "GET",
          "url" => "https://httpbin.org/anything?email={{state.query}}&source=primary",
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 680, "y" => 250},
        "data" => %{
          "name" => "Check Primary",
          "code" => ~S"""
          email = state["query"] || ""
          # Simulate primary miss when email starts with "fallback_"
          found = email != "" and not String.starts_with?(email, "fallback_")

          new_state = Map.put(state, "sources_tried", 1)
          result = Map.put(input, "found", found)
          {result, new_state}
          """
        }
      },
      %{
        "id" => "n5",
        "type" => "condition",
        "position" => %{"x" => 890, "y" => 250},
        "data" => %{
          "name" => "Source 1 Found?",
          "expression" => ~S|if input["found"] == true, do: 0, else: 1|,
          "branch_labels" => %{
            "0" => "Found",
            "1" => "Miss"
          }
        }
      },
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 1100, "y" => 120},
        "data" => %{
          "name" => "Extract Primary",
          "code" => ~S"""
          new_state = state
            |> Map.put("source", "primary")
            |> Map.put("confidence", 90)
            |> Map.put("enriched_name", "Primary Match")
            |> Map.put("enriched_company", "PrimaryCorp")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 1320, "y" => 120},
        "data" => %{
          "name" => "Merge Primary",
          "code" => ~S"""
          {input, state}
          """
        }
      },
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1540, "y" => 120},
        "data" => %{
          "name" => "End (Primary)",
          "response_schema" => [
            %{"name" => "source", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "confidence",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "enriched_name",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "enriched_company",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "sources_tried",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "source", "state_variable" => "source"},
            %{"response_field" => "confidence", "state_variable" => "confidence"},
            %{"response_field" => "enriched_name", "state_variable" => "enriched_name"},
            %{"response_field" => "enriched_company", "state_variable" => "enriched_company"},
            %{"response_field" => "sources_tried", "state_variable" => "sources_tried"}
          ]
        }
      },
      %{
        "id" => "n9",
        "type" => "http_request",
        "position" => %{"x" => 1100, "y" => 380},
        "data" => %{
          "name" => "Fetch Fallback",
          "method" => "GET",
          "url" => "https://httpbin.org/anything?email={{state.query}}&source=fallback",
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },
      %{
        "id" => "n10",
        "type" => "elixir_code",
        "position" => %{"x" => 1320, "y" => 380},
        "data" => %{
          "name" => "Check Fallback",
          "code" => ~S"""
          new_state = Map.put(state, "sources_tried", 2)
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n11",
        "type" => "elixir_code",
        "position" => %{"x" => 1540, "y" => 380},
        "data" => %{
          "name" => "Extract Fallback",
          "code" => ~S"""
          new_state = state
            |> Map.put("source", "fallback")
            |> Map.put("confidence", 60)
            |> Map.put("enriched_name", "Fallback Match")
            |> Map.put("enriched_company", "FallbackCorp")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n12",
        "type" => "elixir_code",
        "position" => %{"x" => 1760, "y" => 380},
        "data" => %{
          "name" => "Merge Fallback",
          "code" => ~S"""
          {input, state}
          """
        }
      },
      %{
        "id" => "n13",
        "type" => "end",
        "position" => %{"x" => 1980, "y" => 380},
        "data" => %{
          "name" => "End (Fallback)",
          "response_schema" => [
            %{"name" => "source", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "confidence",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "enriched_name",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "enriched_company",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "sources_tried",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "source", "state_variable" => "source"},
            %{"response_field" => "confidence", "state_variable" => "confidence"},
            %{"response_field" => "enriched_name", "state_variable" => "enriched_name"},
            %{"response_field" => "enriched_company", "state_variable" => "enriched_company"},
            %{"response_field" => "sources_tried", "state_variable" => "sources_tried"}
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
      %{"id" => "e8", "source" => "n5", "source_port" => 1, "target" => "n9", "target_port" => 0},
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
      %{
        "id" => "e12",
        "source" => "n12",
        "source_port" => 0,
        "target" => "n13",
        "target_port" => 0
      }
    ]
  end
end
