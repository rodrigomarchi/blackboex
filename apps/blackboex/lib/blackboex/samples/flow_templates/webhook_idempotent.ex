defmodule Blackboex.Samples.FlowTemplates.WebhookIdempotent do
  @moduledoc """
  Webhook Idempotent template.

  API infrastructure pattern: verifies an incoming webhook signature, checks
  for duplicate delivery, processes the event only if new, and fails with a
  clear error when the signature is invalid.

  ## Flow graph

      Start → Verify Signature → Is Valid?
        → 1: Fail
        → 0: Check Idempotency → Already Processed?
            → 0: Process Event → Mark Processed → End (Processed)
            → 1: End (Already Processed)
  """

  @doc "Returns the Webhook Idempotent flow template definition."
  @spec template() :: map()
  def template do
    %{
      id: "webhook_idempotent",
      name: "Webhook Idempotent",
      description: "Signature-verified, idempotent webhook ingestion pipeline with dedup",
      category: "API Infrastructure",
      icon: "hero-finger-print",
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
        "position" => %{"x" => 50, "y" => 300},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 30_000,
          "payload_schema" => [
            %{
              "name" => "event_id",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "event_type",
              "type" => "string",
              "required" => true,
              "constraints" => %{"min_length" => 1}
            },
            %{
              "name" => "payload",
              "type" => "object",
              "required" => false,
              "constraints" => %{}
            },
            %{
              "name" => "signature",
              "type" => "string",
              "required" => false,
              "constraints" => %{}
            }
          ],
          "state_schema" => [
            %{
              "name" => "signature_valid",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "is_duplicate",
              "type" => "boolean",
              "required" => false,
              "constraints" => %{},
              "initial_value" => false
            },
            %{
              "name" => "processed_at",
              "type" => "string",
              "required" => false,
              "constraints" => %{},
              "initial_value" => ""
            },
            %{
              "name" => "processing_result",
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
        "position" => %{"x" => 260, "y" => 300},
        "data" => %{
          "name" => "Verify Signature",
          "code" => ~S"""
          signature = input["signature"]

          valid =
            cond do
              is_nil(signature) -> true
              is_binary(signature) and String.starts_with?(signature, "valid_") -> true
              is_binary(signature) and String.starts_with?(signature, "invalid_") -> false
              true -> false
            end

          new_state = Map.put(state, "signature_valid", valid)
          result = Map.put(input, "signature_valid", valid)
          {result, new_state}
          """
        }
      },
      %{
        "id" => "n3",
        "type" => "condition",
        "position" => %{"x" => 470, "y" => 300},
        "data" => %{
          "name" => "Is Valid?",
          "expression" => ~S|if input["signature_valid"] == true, do: 0, else: 1|,
          "branch_labels" => %{
            "0" => "Valid",
            "1" => "Invalid"
          }
        }
      },
      %{
        "id" => "n4",
        "type" => "elixir_code",
        "position" => %{"x" => 700, "y" => 180},
        "data" => %{
          "name" => "Check Idempotency",
          "code" => ~S"""
          event_id = input["event_id"] || ""
          is_dup = String.starts_with?(event_id, "dup_")
          new_state = Map.put(state, "is_duplicate", is_dup)
          result = Map.put(input, "is_duplicate", is_dup)
          {result, new_state}
          """
        }
      },
      %{
        "id" => "n5",
        "type" => "condition",
        "position" => %{"x" => 910, "y" => 180},
        "data" => %{
          "name" => "Already Processed?",
          "expression" => ~S|if input["is_duplicate"] == true, do: 1, else: 0|,
          "branch_labels" => %{
            "0" => "New",
            "1" => "Duplicate"
          }
        }
      },
      %{
        "id" => "n6",
        "type" => "elixir_code",
        "position" => %{"x" => 1130, "y" => 80},
        "data" => %{
          "name" => "Process Event",
          "code" => ~S"""
          event_type = input["event_type"] || ""
          result_msg = "processed:" <> event_type
          new_state = Map.put(state, "processing_result", result_msg)
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n7",
        "type" => "elixir_code",
        "position" => %{"x" => 1340, "y" => 80},
        "data" => %{
          "name" => "Mark Processed",
          "code" => ~S"""
          new_state = Map.put(state, "processed_at", "2026-04-10T00:00:00Z")
          {input, new_state}
          """
        }
      },
      %{
        "id" => "n8",
        "type" => "end",
        "position" => %{"x" => 1560, "y" => 80},
        "data" => %{
          "name" => "End (Processed)",
          "response_schema" => [
            %{
              "name" => "signature_valid",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "is_duplicate",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "processed_at",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "processing_result",
              "type" => "string",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "signature_valid", "state_variable" => "signature_valid"},
            %{"response_field" => "is_duplicate", "state_variable" => "is_duplicate"},
            %{"response_field" => "processed_at", "state_variable" => "processed_at"},
            %{"response_field" => "processing_result", "state_variable" => "processing_result"}
          ]
        }
      },
      %{
        "id" => "n9",
        "type" => "end",
        "position" => %{"x" => 1130, "y" => 280},
        "data" => %{
          "name" => "End (Already Processed)",
          "response_schema" => [
            %{
              "name" => "signature_valid",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            },
            %{
              "name" => "is_duplicate",
              "type" => "boolean",
              "required" => true,
              "constraints" => %{}
            }
          ],
          "response_mapping" => [
            %{"response_field" => "signature_valid", "state_variable" => "signature_valid"},
            %{"response_field" => "is_duplicate", "state_variable" => "is_duplicate"}
          ]
        }
      },
      %{
        "id" => "n10",
        "type" => "fail",
        "position" => %{"x" => 700, "y" => 460},
        "data" => %{
          "name" => "Invalid Signature",
          "message" => ~S|"Invalid webhook signature for event #{input["event_id"]}"|,
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
      %{"id" => "e5", "source" => "n5", "source_port" => 0, "target" => "n6", "target_port" => 0},
      %{"id" => "e6", "source" => "n6", "source_port" => 0, "target" => "n7", "target_port" => 0},
      %{"id" => "e7", "source" => "n7", "source_port" => 0, "target" => "n8", "target_port" => 0},
      %{"id" => "e8", "source" => "n5", "source_port" => 1, "target" => "n9", "target_port" => 0},
      %{
        "id" => "e9",
        "source" => "n3",
        "source_port" => 1,
        "target" => "n10",
        "target_port" => 0
      }
    ]
  end
end
