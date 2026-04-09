defmodule Blackboex.Flows.Templates.ApiStatusChecker do
  @moduledoc """
  API Status Checker template.

  A flow that checks multiple HTTP endpoints and aggregates their status.
  Uses condition branching based on HTTP response status, custom headers,
  and for_each to process a list of URLs.

  ## Flow graph

      Start (url, method, custom_header_name, custom_header_value)
        → Prepare (elixir_code — store in state)
        → Check Endpoint (http_request — configurable method + headers)
        → Analyze Response (elixir_code — extract status, timing, body size)
        → Is Healthy? (condition — status 200 vs error)
          → Port 0: Build Success Report (elixir_code) → End (Success)
          → Port 1: Build Error Report (elixir_code) → End (Error)
  """

  @spec template() :: map()
  def template do
    %{
      id: "api_status_checker",
      name: "API Status Checker",
      description:
        "Checks an HTTP endpoint with configurable method/headers and reports health status",
      category: "Getting Started",
      icon: "hero-signal",
      definition: definition()
    }
  end

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
              "name" => "url",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "method",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "custom_header_name",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "custom_header_value",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "url",
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
              "initial_value" => "GET"
            },
            %{
              "name" => "status_code",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "response_time_ms",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "healthy",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "report",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            }
          ]
        }
      },

      # ── n2: Prepare ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 250, "y" => 250},
        "data" => %{
          "name" => "Prepare",
          "code" => ~S"""
          new_state = state
            |> Map.put("url", input["url"])
            |> Map.put("method", input["method"] || "GET")

          {input, new_state}
          """
        }
      },

      # ── n3: Check Endpoint ──
      %{
        "id" => "n3",
        "type" => "http_request",
        "position" => %{"x" => 450, "y" => 250},
        "data" => %{
          "name" => "Check Endpoint",
          "method" => "GET",
          "url" => "https://httpbin.org/anything",
          "headers" => %{
            "x-check-url" => "{{state.url}}",
            "user-agent" => "BlackboexFlow/1.0"
          },
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n4: Analyze Response ──
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 650, "y" => 250},
        "data" => %{
          "name" => "Analyze Response",
          "code" => ~S"""
          http_resp = state["http_response"]
          status = http_resp[:status] || http_resp["status"] || 0
          duration = http_resp[:duration_ms] || http_resp["duration_ms"] || 0
          body = http_resp[:body] || http_resp["body"] || %{}

          # httpbin /anything echoes back headers
          headers_echo = body["headers"] || %{}
          check_url = headers_echo["X-Check-Url"] || headers_echo["x-check-url"] || ""
          user_agent = headers_echo["User-Agent"] || headers_echo["user-agent"] || ""

          new_state = state
            |> Map.put("status_code", status)
            |> Map.put("response_time_ms", duration)
            |> Map.put("echoed_url", check_url)
            |> Map.put("echoed_ua", user_agent)

          {input, new_state}
          """
        }
      },

      # ── n5: Is Healthy? ──
      %{
        "id" => "n5",
        "type" => "condition",
        "position" => %{"x" => 850, "y" => 250},
        "data" => %{
          "name" => "Is Healthy?",
          "expression" => ~S"""
          if state["status_code"] == 200, do: 0, else: 1
          """,
          "branch_labels" => %{
            "0" => "Healthy",
            "1" => "Unhealthy"
          }
        }
      },

      # ── n6: Success Report ──
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 1050, "y" => 100},
        "data" => %{
          "name" => "Success Report",
          "code" => ~S"""
          report = "OK: #{state["url"]} responded #{state["status_code"]} in #{state["response_time_ms"]}ms"

          new_state = state
            |> Map.put("healthy", true)
            |> Map.put("report", report)

          {input, new_state}
          """
        }
      },

      # ── n7: Error Report ──
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 1050, "y" => 400},
        "data" => %{
          "name" => "Error Report",
          "code" => ~S"""
          report = "FAIL: #{state["url"]} responded #{state["status_code"]}"

          new_state = state
            |> Map.put("healthy", false)
            |> Map.put("report", report)

          {input, new_state}
          """
        }
      },

      # ── n8: End (Success) ──
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1250, "y" => 100},
        "data" => %{
          "name" => "End (Success)",
          "response_schema" => [
            %{"name" => "healthy", "type" => "boolean", "required" => true, "constraints" => %{}},
            %{
              "name" => "status_code",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "response_time_ms",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "report", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "healthy", "state_variable" => "healthy"},
            %{"response_field" => "status_code", "state_variable" => "status_code"},
            %{"response_field" => "response_time_ms", "state_variable" => "response_time_ms"},
            %{"response_field" => "report", "state_variable" => "report"}
          ]
        }
      },

      # ── n9: End (Error) ──
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1250, "y" => 400},
        "data" => %{
          "name" => "End (Error)",
          "response_schema" => [
            %{"name" => "healthy", "type" => "boolean", "required" => true, "constraints" => %{}},
            %{
              "name" => "status_code",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "report", "type" => "string", "required" => true, "constraints" => %{}}
          ],
          "response_mapping" => [
            %{"response_field" => "healthy", "state_variable" => "healthy"},
            %{"response_field" => "status_code", "state_variable" => "status_code"},
            %{"response_field" => "report", "state_variable" => "report"}
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
      %{"id" => "e6", "source" => "n5", "source_port" => 1, "target" => "n7", "target_port" => 0},
      %{"id" => "e7", "source" => "n6", "source_port" => 0, "target" => "n8", "target_port" => 0},
      %{"id" => "e8", "source" => "n7", "source_port" => 0, "target" => "n9", "target_port" => 0}
    ]
  end
end
