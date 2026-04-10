defmodule Blackboex.Flows.Templates.BatchProcessor do
  @moduledoc """
  Batch Processor template.

  A real-world flow that fetches posts from a public REST API, then uses
  for_each to process each post — extracting titles and counting words.
  Finally aggregates the results into summary statistics.

  Exercises: http_request → response parsing → for_each over API data →
  body_code with business logic → accumulator → aggregation → response mapping.

  ## Flow graph

      Start (limit: integer)
        → Prepare (elixir_code — store limit in state)
        → Fetch Posts (http_request GET jsonplaceholder /posts)
        → Extract Posts (elixir_code — parse body, slice to limit)
        → Process Each Post (for_each — extract title + word count)
        → Aggregate (elixir_code — stats: total posts, avg words, longest title)
        → End (response mapping)
  """

  @spec template() :: map()
  def template do
    %{
      id: "batch_processor",
      name: "Batch Processor",
      description:
        "Fetches posts from a REST API, processes each with for_each — real-world iteration over HTTP data",
      category: "Data Processing",
      icon: "hero-queue-list",
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
              "name" => "limit",
              "type" => "integer",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "limit",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 5
            },
            %{
              "name" => "posts",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "object"},
              "initial_value" => []
            },
            %{
              "name" => "processed",
              "type" => "array",
              "required" => false,
              "constraints" => %{"item_type" => "object"},
              "initial_value" => []
            },
            %{
              "name" => "total_posts",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "avg_words",
              "type" => "float",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0.0
            },
            %{
              "name" => "longest_title",
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
        "position" => %{"x" => 230, "y" => 200},
        "data" => %{
          "name" => "Prepare",
          "code" => ~S"""
          limit = input["limit"] || 5
          {input, Map.put(state, "limit", limit)}
          """
        }
      },

      # ── n3: Fetch Posts ──
      %{
        "id" => "n3",
        "type" => "http_request",
        "position" => %{"x" => 410, "y" => 200},
        "data" => %{
          "name" => "Fetch Posts",
          "method" => "GET",
          "url" => "https://jsonplaceholder.typicode.com/posts",
          "timeout_ms" => 10_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n4: Extract Posts ──
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 590, "y" => 200},
        "data" => %{
          "name" => "Extract Posts",
          "code" => ~S"""
          http_resp = state["http_response"]
          body = http_resp[:body] || http_resp["body"] || []

          posts =
            body
            |> Enum.take(state["limit"])
            |> Enum.map(fn post ->
              %{
                "id" => post["id"],
                "title" => post["title"] || "",
                "body" => post["body"] || ""
              }
            end)

          {input, Map.put(state, "posts", posts)}
          """
        }
      },

      # ── n5: Process Each Post (for_each) ──
      %{
        "id" => "n5",
        "type" => "for_each",
        "position" => %{"x" => 770, "y" => 200},
        "data" => %{
          "name" => "Process Each Post",
          "source_expression" => ~S'Map.get(state, "posts", [])',
          "body_code" => ~S"""
          title = item["title"] || ""
          body_text = item["body"] || ""
          word_count = body_text |> String.split(~r/\s+/, trim: true) |> length()

          %{
            "id" => item["id"],
            "title" => title,
            "word_count" => word_count,
            "title_length" => String.length(title)
          }
          """,
          "item_variable" => "item",
          "accumulator" => "processed",
          "batch_size" => 10
        }
      },

      # ── n6: Aggregate ──
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 950, "y" => 200},
        "data" => %{
          "name" => "Aggregate",
          "code" => ~S"""
          processed = state["processed"]
          total = length(processed)

          total_words = Enum.reduce(processed, 0, fn p, acc -> acc + p["word_count"] end)
          avg_words = if total > 0, do: Float.round(total_words / total, 1), else: 0.0

          longest =
            processed
            |> Enum.max_by(fn p -> p["title_length"] end, fn -> %{"title" => ""} end)
            |> Map.get("title", "")

          new_state = state
            |> Map.put("total_posts", total)
            |> Map.put("avg_words", avg_words)
            |> Map.put("longest_title", longest)

          {input, new_state}
          """
        }
      },

      # ── n7: End ──
      %{
        "id" => "n7",
        "type" => "end",
        "position" => %{"x" => 1130, "y" => 200},
        "data" => %{
          "name" => "End",
          "response_schema" => [
            %{
              "name" => "total_posts",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{"name" => "avg_words", "type" => "float", "required" => true, "constraints" => %{}},
            %{
              "name" => "longest_title",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "total_posts", "state_variable" => "total_posts"},
            %{"response_field" => "avg_words", "state_variable" => "avg_words"},
            %{"response_field" => "longest_title", "state_variable" => "longest_title"}
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
