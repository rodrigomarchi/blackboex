defmodule Blackboex.Flows.Templates.AsyncJobPoller do
  @moduledoc """
  Async Job Dispatch with Polling template.

  Submits a long-running asynchronous job (video transcoding, ML inference,
  report generation) and polls for status with delays until completion or
  timeout. Demonstrates the classic async dispatch + polling loop pattern
  essential for AI/ML integrations (Replicate, Deepgram, AWS Batch).

  ## Flow graph

      Start (job_type, input_url, callback_url?, simulate_job_id?)
        → Submit Job (elixir_code — generate job_id)
        → Call Submit API (http_request)
        → Extract Job ID (elixir_code)
        → Wait Before Poll 1 (delay)
        → Poll Status (1) (http_request)
        → Check Status (1) (elixir_code — simulate based on simulate_job_id)
        → Done After Poll 1? (condition: 3-way)
          → Port 0 (done):    Extract Result (Poll 1) → End (Completed Poll 1)
          → Port 1 (running): Wait Before Poll 2 → Poll Status (2) → Check Status (2)
              → Done After Poll 2? (condition: 3-way)
                → Port 0 (done):    Extract Result (Poll 2) → End (Completed Poll 2)
                → Port 1 (timeout): Mark Timeout → Fail (Job Timeout)
                → Port 2 (error):   Fail (Job Failed - Poll 2)
          → Port 2 (error):   Fail (Job Failed)
  """

  @doc "Returns the Async Job Poller flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "async_job_poller",
      name: "Async Job Dispatch with Polling",
      description:
        "Submits a long-running job and polls for completion — video transcoding, ML inference, report generation",
      category: "Integrations",
      icon: "hero-arrow-path-rounded-square",
      definition: definition()
    }
  end

  @doc false
  @spec definition() :: map()
  def definition do
    %{"version" => "1.0", "nodes" => nodes(), "edges" => edges()}
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
          "timeout" => 120_000,
          "payload_schema" => [
            %{"name" => "job_type", "type" => "string", "required" => true, "constraints" => %{}},
            %{
              "name" => "input_url",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "callback_url",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "simulate_job_id",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "job_id",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "poll_count",
              "type" => "integer",
              "required" => false,
              "constraints" => %{},
              "initial_value" => 0
            },
            %{
              "name" => "job_status",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => "pending"
            },
            %{
              "name" => "result_url",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "submitted_at",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "error_message",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            }
          ]
        }
      },

      # ── n2: Submit Job ──
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 270, "y" => 250},
        "data" => %{
          "name" => "Submit Job",
          "code" => ~S"""
          simulate = input["simulate_job_id"]
          job_id = if simulate && simulate != "", do: simulate, else: "job_#{:rand.uniform(9999)}"
          submitted_at = DateTime.utc_now() |> DateTime.to_iso8601()

          new_state =
            state
            |> Map.put("job_id", job_id)
            |> Map.put("submitted_at", submitted_at)
            |> Map.put("job_status", "submitted")

          {input, new_state}
          """
        }
      },

      # ── n3: Call Submit API ──
      %{
        "id" => "n3",
        "type" => "http_request",
        "position" => %{"x" => 490, "y" => 250},
        "data" => %{
          "name" => "Call Submit API",
          "method" => "POST",
          "url" => "https://httpbin.org/post",
          "headers" => %{"content-type" => "application/json"},
          "body_template" =>
            ~S|{"job_type": "{{input.job_type}}", "input_url": "{{input.input_url}}", "job_id": "{{state.job_id}}"}|,
          "timeout_ms" => 15_000,
          "max_retries" => 1,
          "expected_status" => [200]
        }
      },

      # ── n4: Extract Job ID ──
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 710, "y" => 250},
        "data" => %{
          "name" => "Extract Job ID",
          "code" => ~S"""
          {input, Map.put(state, "job_status", "running")}
          """
        }
      },

      # ── n5: Wait Before Poll 1 ──
      %{
        "id" => "n5",
        "type" => "delay",
        "position" => %{"x" => 930, "y" => 250},
        "data" => %{
          "name" => "Wait Before Poll 1",
          "duration_ms" => 10,
          "max_duration_ms" => 5_000
        }
      },

      # ── n6: Poll Status (1) ──
      %{
        "id" => "n6",
        "type" => "http_request",
        "position" => %{"x" => 1150, "y" => 250},
        "data" => %{
          "name" => "Poll Status (1)",
          "method" => "GET",
          "url" => "https://httpbin.org/anything?job_id={{state.job_id}}",
          "headers" => %{},
          "timeout_ms" => 10_000,
          "max_retries" => 0,
          "expected_status" => [200]
        }
      },

      # ── n7: Check Status (1) ──
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 1370, "y" => 250},
        "data" => %{
          "name" => "Check Status (1)",
          "code" => ~S"""
          job_id = state["job_id"]
          poll_count = (state["poll_count"] || 0) + 1

          {new_status, error_msg} =
            cond do
              job_id == "complete_immediately" -> {"done", ""}
              job_id == "fail_on_poll" -> {"error", "Job processing failed: invalid input format"}
              true -> {"running", ""}
            end

          new_state =
            state
            |> Map.put("job_status", new_status)
            |> Map.put("poll_count", poll_count)
            |> Map.put("error_message", error_msg)

          {input, new_state}
          """
        }
      },

      # ── n8: Done After Poll 1? ──
      %{
        "id" => "n8",
        "type" => "condition",
        "position" => %{"x" => 1590, "y" => 250},
        "data" => %{
          "name" => "Done After Poll 1?",
          "expression" => ~S"""
          case state["job_status"] do
            "done" -> 0
            "error" -> 2
            _ -> 1
          end
          """,
          "branch_labels" => %{"0" => "Completed", "1" => "Still Running", "2" => "Failed"}
        }
      },

      # ── n9: Extract Result (Poll 1) ──
      %{
        "id" => "n9",
        "type" => "elixir_code",
        "position" => %{"x" => 1810, "y" => 100},
        "data" => %{
          "name" => "Extract Result (Poll 1)",
          "code" => ~S"""
          result_url = "https://storage.example.com/results/#{state["job_id"]}"

          new_state =
            state
            |> Map.put("result_url", result_url)
            |> Map.put("job_status", "completed")

          {input, new_state}
          """
        }
      },

      # ── n10: End (Completed Poll 1) ──
      %{
        "id" => "n10",
        "type" => "end",
        "position" => %{"x" => 2010, "y" => 100},
        "data" => %{
          "name" => "End (Completed Poll 1)",
          "response_schema" => [
            %{
              "name" => "job_id",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "job_status",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "poll_count",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "result_url",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "job_id", "state_variable" => "job_id"},
            %{"response_field" => "job_status", "state_variable" => "job_status"},
            %{"response_field" => "poll_count", "state_variable" => "poll_count"},
            %{"response_field" => "result_url", "state_variable" => "result_url"}
          ]
        }
      },

      # ── n11: Wait Before Poll 2 ──
      %{
        "id" => "n11",
        "type" => "delay",
        "position" => %{"x" => 1810, "y" => 250},
        "data" => %{
          "name" => "Wait Before Poll 2",
          "duration_ms" => 10,
          "max_duration_ms" => 5_000
        }
      },

      # ── n12: Poll Status (2) ──
      %{
        "id" => "n12",
        "type" => "http_request",
        "position" => %{"x" => 2010, "y" => 250},
        "data" => %{
          "name" => "Poll Status (2)",
          "method" => "GET",
          "url" => "https://httpbin.org/anything?job_id={{state.job_id}}&poll=2",
          "headers" => %{},
          "timeout_ms" => 10_000,
          "max_retries" => 0,
          "expected_status" => [200]
        }
      },

      # ── n13: Check Status (2) ──
      %{
        "id" => "n13",
        "type" => "elixir_code",
        "position" => %{"x" => 2210, "y" => 250},
        "data" => %{
          "name" => "Check Status (2)",
          "code" => ~S"""
          poll_count = (state["poll_count"] || 0) + 1

          new_state =
            state
            |> Map.put("job_status", "done")
            |> Map.put("poll_count", poll_count)

          {input, new_state}
          """
        }
      },

      # ── n14: Done After Poll 2? ──
      %{
        "id" => "n14",
        "type" => "condition",
        "position" => %{"x" => 2410, "y" => 250},
        "data" => %{
          "name" => "Done After Poll 2?",
          "expression" => ~S"""
          case state["job_status"] do
            "done" -> 0
            "error" -> 2
            _ -> 1
          end
          """,
          "branch_labels" => %{"0" => "Completed", "1" => "Timeout", "2" => "Failed"}
        }
      },

      # ── n15: Extract Result (Poll 2) ──
      %{
        "id" => "n15",
        "type" => "elixir_code",
        "position" => %{"x" => 2630, "y" => 150},
        "data" => %{
          "name" => "Extract Result (Poll 2)",
          "code" => ~S"""
          result_url = "https://storage.example.com/results/#{state["job_id"]}"

          new_state =
            state
            |> Map.put("result_url", result_url)
            |> Map.put("job_status", "completed")

          {input, new_state}
          """
        }
      },

      # ── n16: End (Completed Poll 2) ──
      %{
        "id" => "n16",
        "type" => "end",
        "position" => %{"x" => 2830, "y" => 150},
        "data" => %{
          "name" => "End (Completed Poll 2)",
          "response_schema" => [
            %{
              "name" => "job_id",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "job_status",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "poll_count",
              "type" => "integer",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "result_url",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "job_id", "state_variable" => "job_id"},
            %{"response_field" => "job_status", "state_variable" => "job_status"},
            %{"response_field" => "poll_count", "state_variable" => "poll_count"},
            %{"response_field" => "result_url", "state_variable" => "result_url"}
          ]
        }
      },

      # ── n17: Mark Timeout ──
      %{
        "id" => "n17",
        "type" => "elixir_code",
        "position" => %{"x" => 2630, "y" => 300},
        "data" => %{
          "name" => "Mark Timeout",
          "code" => ~S"""
          {input, Map.put(state, "job_status", "timeout")}
          """
        }
      },

      # ── n18: Fail (Job Timeout) ──
      %{
        "id" => "n18",
        "type" => "fail",
        "position" => %{"x" => 2830, "y" => 300},
        "data" => %{
          "name" => "Job Timeout",
          "message" => ~S|"Job #{state["job_id"]} timed out after #{state["poll_count"]} polls"|
        }
      },

      # ── n19: Fail (Job Failed - from Poll 1) ──
      %{
        "id" => "n19",
        "type" => "fail",
        "position" => %{"x" => 1810, "y" => 400},
        "data" => %{
          "name" => "Job Failed",
          "message" => ~S|"Job #{state["job_id"]} failed: #{state["error_message"]}"|
        }
      },

      # ── n20: Fail (Job Failed - from Poll 2) ──
      %{
        "id" => "n20",
        "type" => "fail",
        "position" => %{"x" => 2630, "y" => 450},
        "data" => %{
          "name" => "Job Failed (Poll 2)",
          "message" => ~S|"Job #{state["job_id"]} failed: #{state["error_message"]}"|
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
      # Poll 1: done
      %{"id" => "e8", "source" => "n8", "source_port" => 0, "target" => "n9", "target_port" => 0},
      %{
        "id" => "e9",
        "source" => "n9",
        "source_port" => 0,
        "target" => "n10",
        "target_port" => 0
      },
      # Poll 1: still running → poll 2
      %{
        "id" => "e10",
        "source" => "n8",
        "source_port" => 1,
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
      },
      %{
        "id" => "e13",
        "source" => "n13",
        "source_port" => 0,
        "target" => "n14",
        "target_port" => 0
      },
      # Poll 1: error
      %{
        "id" => "e14",
        "source" => "n8",
        "source_port" => 2,
        "target" => "n19",
        "target_port" => 0
      },
      # Poll 2: done
      %{
        "id" => "e15",
        "source" => "n14",
        "source_port" => 0,
        "target" => "n15",
        "target_port" => 0
      },
      %{
        "id" => "e16",
        "source" => "n15",
        "source_port" => 0,
        "target" => "n16",
        "target_port" => 0
      },
      # Poll 2: timeout
      %{
        "id" => "e17",
        "source" => "n14",
        "source_port" => 1,
        "target" => "n17",
        "target_port" => 0
      },
      %{
        "id" => "e18",
        "source" => "n17",
        "source_port" => 0,
        "target" => "n18",
        "target_port" => 0
      },
      # Poll 2: error
      %{
        "id" => "e19",
        "source" => "n14",
        "source_port" => 2,
        "target" => "n20",
        "target_port" => 0
      }
    ]
  end
end
