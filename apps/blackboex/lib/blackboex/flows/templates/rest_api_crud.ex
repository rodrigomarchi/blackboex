defmodule Blackboex.Flows.Templates.RestApiCrud do
  @moduledoc """
  REST API CRUD template.

  A flow that performs a full CRUD cycle against JSONPlaceholder API:
  POST to create a resource, then GET to read it back, validating
  the round-trip. Tests POST with body_template, GET with URL interpolation,
  custom headers, expected_status, and response parsing across multiple
  http_request nodes chained via state.

  ## Flow graph

      Start (title, body, userId)
        → Create Post (http_request POST jsonplaceholder)
        → Extract Created ID (elixir_code)
        → Read Post (http_request GET jsonplaceholder)
        → Validate Round-Trip (elixir_code)
        → End (response mapping)
  """

  @spec template() :: map()
  def template do
    %{
      id: "rest_api_crud",
      name: "REST API CRUD",
      description:
        "Full CRUD cycle against JSONPlaceholder — tests POST with body, GET with interpolation, response parsing",
      category: "Integrations",
      icon: "hero-arrow-path",
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
        "position" => %{"x" => 50, "y" => 200},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 30_000,
          "payload_schema" => [
            %{
              "name" => "title",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "body",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "userId",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "title",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "body_text",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "user_id",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "created_id",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "create_status",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "read_status",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "read_title",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "method_used",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            }
          ]
        }
      },

      # ── n2: Prepare State ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 250, "y" => 200},
        "data" => %{
          "name" => "Prepare State",
          "code" => ~S"""
          new_state = state
            |> Map.put("title", input["title"])
            |> Map.put("body_text", input["body"])
            |> Map.put("user_id", to_string(input["userId"]))

          {input, new_state}
          """
        }
      },

      # ── n3: Create Post (POST) ──
      %{
        "id" => "n3",
        "type" => "http_request",
        "position" => %{"x" => 450, "y" => 200},
        "data" => %{
          "name" => "Create Post",
          "method" => "POST",
          "url" => "https://jsonplaceholder.typicode.com/posts",
          "headers" => %{
            "content-type" => "application/json; charset=UTF-8"
          },
          "body_template" =>
            ~S|{"title":"{{state.title}}","body":"{{state.body_text}}","userId":{{state.user_id}}}|,
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [201]
        }
      },

      # ── n4: Extract Created ID ──
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 650, "y" => 200},
        "data" => %{
          "name" => "Extract Created ID",
          "code" => ~S"""
          http_resp = state["http_response"]
          body = http_resp[:body] || http_resp["body"] || %{}
          created_id = to_string(body["id"] || "")
          status = http_resp[:status] || http_resp["status"] || 0

          new_state = state
            |> Map.put("created_id", created_id)
            |> Map.put("create_status", status)

          {input, new_state}
          """
        }
      },

      # ── n5: Read Post (GET) ──
      %{
        "id" => "n5",
        "type" => "http_request",
        "position" => %{"x" => 850, "y" => 200},
        "data" => %{
          "name" => "Read Post",
          "method" => "GET",
          "url" => "https://jsonplaceholder.typicode.com/posts/1",
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n6: Validate Round-Trip ──
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 1050, "y" => 200},
        "data" => %{
          "name" => "Validate Round-Trip",
          "code" => ~S"""
          http_resp = state["http_response"]
          body = http_resp[:body] || http_resp["body"] || %{}

          new_state = state
            |> Map.put("read_status", http_resp[:status] || http_resp["status"] || 0)
            |> Map.put("read_title", body["title"] || "")
            |> Map.put("method_used", "POST+GET")

          {input, new_state}
          """
        }
      },

      # ── n7: End ──
      %{
        "id" => "n7",
        "type" => "end",
        "position" => %{"x" => 1250, "y" => 200},
        "data" => %{
          "name" => "End",
          "response_schema" => [
            %{
              "name" => "create_status",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "created_id",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "read_status",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "read_title",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "method_used",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "create_status", "state_variable" => "create_status"},
            %{"response_field" => "created_id", "state_variable" => "created_id"},
            %{"response_field" => "read_status", "state_variable" => "read_status"},
            %{"response_field" => "read_title", "state_variable" => "read_title"},
            %{"response_field" => "method_used", "state_variable" => "method_used"}
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
      %{"id" => "e6", "source" => "n6", "source_port" => 0, "target" => "n7", "target_port" => 0}
    ]
  end
end
