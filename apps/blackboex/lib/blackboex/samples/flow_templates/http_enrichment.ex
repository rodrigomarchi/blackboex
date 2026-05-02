defmodule Blackboex.Samples.FlowTemplates.HttpEnrichment do
  @moduledoc """
  HTTP Enrichment template.

  A flow that prepares a request, calls an external HTTP API,
  and extracts data from the response. Tests http_request node
  with URL interpolation and response parsing.

  ## Flow graph

      Start (query: string)
        → Prepare Request (elixir_code — build URL params)
        → Fetch Data (http_request — GET httpbin.org/anything)
        → Extract Response (elixir_code — parse HTTP body)
        → End (response mapping)
  """

  @doc "Returns the HTTP Enrichment flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "http_enrichment",
      name: "HTTP Enrichment",
      description:
        "Calls an external HTTP API and extracts response data — tests http_request with interpolation",
      category: "Integrations",
      icon: "hero-globe-alt",
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
          "timeout" => 30_000,
          "payload_schema" => [
            %{
              "name" => "query",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            }
          ],
          "state_schema" => [
            %{
              "name" => "query",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "http_status",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "response_url",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "method",
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
        "position" => %{"x" => 280, "y" => 200},
        "data" => %{
          "name" => "Prepare Request",
          "code" => ~S"""
          new_state = Map.put(state, "query", input["query"])
          {input, new_state}
          """
        }
      },

      # ── n3: Fetch Data (http_request) ──
      %{
        "id" => "n3",
        "type" => "http_request",
        "position" => %{"x" => 510, "y" => 200},
        "data" => %{
          "name" => "Fetch Data",
          "method" => "GET",
          "url" => "https://httpbin.org/anything?q={{state.query}}",
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n4: Extract Response ──
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 740, "y" => 200},
        "data" => %{
          "name" => "Extract Response",
          "code" => ~S"""
          http_resp = state["http_response"]
          body = http_resp[:body] || http_resp["body"] || %{}

          url = body["url"] || ""
          method = body["method"] || ""

          new_state = state
            |> Map.put("http_status", http_resp[:status] || http_resp["status"] || 0)
            |> Map.put("response_url", url)
            |> Map.put("method", method)

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
              "name" => "http_status",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "response_url",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "method", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "http_status", "state_variable" => "http_status"},
            %{"response_field" => "response_url", "state_variable" => "response_url"},
            %{"response_field" => "method", "state_variable" => "method"}
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
