defmodule Blackboex.Flows.Templates.DataPipeline do
  @moduledoc """
  Data Pipeline template.

  A 5-node linear flow that transforms data through multiple stages,
  testing deep state mutation chains and data accumulation.

  ## Flow graph

      Start (records: list of maps)
        → Parse Records (elixir_code — extract/validate)
        → Enrich Data (elixir_code — compute derived fields)
        → Aggregate (elixir_code — summary stats)
        → End (response mapping)
  """

  @doc "Returns the Data Pipeline flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "data_pipeline",
      name: "Data Pipeline",
      description:
        "A multi-stage pipeline that parses, enriches, and aggregates records — tests deep state mutation chains",
      category: "Getting Started",
      icon: "hero-funnel",
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
      # ── n1: Start ──
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 50, "y" => 200},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 15_000,
          "payload_schema" => [
            %{
              "name" => "records",
              "type" => "array",
              "required" => true,
              "constraints" => %{"item_type" => "object"}
            }
          ],
          "state_schema" => [
            %{
              "name" => "parsed",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "object"},
              "initial_value" => []
            },
            %{
              "name" => "enriched",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "object"},
              "initial_value" => []
            },
            %{
              "name" => "total_amount",
              "type" => "float",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0.0
            },
            %{
              "name" => "record_count",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "avg_amount",
              "type" => "float",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0.0
            }
          ]
        }
      },

      # ── n2: Parse Records ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 280, "y" => 200},
        "data" => %{
          "name" => "Parse Records",
          "code" => ~S"""
          records = input["records"] || []

          parsed =
            Enum.map(records, fn rec ->
              %{
                "name" => rec["name"] || "unknown",
                "amount" => (rec["amount"] || 0) * 1.0,
                "category" => rec["category"] || "other"
              }
            end)

          {input, Map.put(state, "parsed", parsed)}
          """
        }
      },

      # ── n3: Enrich Data ──
      %{
        "id" => "n3",
        "type" => "elixir_code",
        "position" => %{"x" => 510, "y" => 200},
        "data" => %{
          "name" => "Enrich Data",
          "code" => ~S"""
          parsed = state["parsed"]

          enriched =
            Enum.map(parsed, fn rec ->
              tier =
                cond do
                  rec["amount"] >= 100 -> "premium"
                  rec["amount"] >= 50 -> "standard"
                  true -> "basic"
                end

              Map.put(rec, "tier", tier)
            end)

          {input, Map.put(state, "enriched", enriched)}
          """
        }
      },

      # ── n4: Aggregate ──
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 740, "y" => 200},
        "data" => %{
          "name" => "Aggregate",
          "code" => ~S"""
          enriched = state["enriched"]
          count = length(enriched)
          total = Enum.reduce(enriched, 0.0, fn rec, acc -> acc + rec["amount"] end)
          avg = if count > 0, do: total / count, else: 0.0

          new_state = state
            |> Map.put("record_count", count)
            |> Map.put("total_amount", total)
            |> Map.put("avg_amount", avg)

          {input, new_state}
          """
        }
      },

      # ── n5: End ──
      %{
        "id" => "n5",
        "type" => "end",
        "position" => %{"x" => 970, "y" => 200},
        "data" => %{
          "name" => "End",
          "response_schema" => [
            %{
              "name" => "record_count",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "total_amount",
              "type" => "float",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "avg_amount", "type" => "float", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "record_count", "state_variable" => "record_count"},
            %{"response_field" => "total_amount", "state_variable" => "total_amount"},
            %{"response_field" => "avg_amount", "state_variable" => "avg_amount"}
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
      %{"id" => "e4", "source" => "n4", "source_port" => 0, "target" => "n5", "target_port" => 0}
    ]
  end
end
