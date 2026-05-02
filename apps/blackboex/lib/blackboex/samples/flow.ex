defmodule Blackboex.Samples.Flow do
  @moduledoc """
  Flow samples in the platform-wide sample catalogue.
  """

  alias Blackboex.Samples.Id

  @template_modules [
    Blackboex.Samples.FlowTemplates.HelloWorld,
    Blackboex.Samples.FlowTemplates.Notification,
    Blackboex.Samples.FlowTemplates.AllNodesDemo,
    Blackboex.Samples.FlowTemplates.DataPipeline,
    Blackboex.Samples.FlowTemplates.OrderProcessor,
    Blackboex.Samples.FlowTemplates.BatchProcessor,
    Blackboex.Samples.FlowTemplates.HttpEnrichment,
    Blackboex.Samples.FlowTemplates.ApprovalWorkflow,
    Blackboex.Samples.FlowTemplates.RestApiCrud,
    Blackboex.Samples.FlowTemplates.ApiStatusChecker,
    Blackboex.Samples.FlowTemplates.AdvancedFeatures,
    Blackboex.Samples.FlowTemplates.LeadScoring,
    Blackboex.Samples.FlowTemplates.WebhookProcessor,
    Blackboex.Samples.FlowTemplates.SupportTicketRouter,
    Blackboex.Samples.FlowTemplates.EscalationApproval,
    Blackboex.Samples.FlowTemplates.DataEnrichmentChain,
    Blackboex.Samples.FlowTemplates.IncidentAlertPipeline,
    Blackboex.Samples.FlowTemplates.CustomerOnboarding,
    Blackboex.Samples.FlowTemplates.WebhookIdempotent,
    Blackboex.Samples.FlowTemplates.AbandonedCartRecovery,
    Blackboex.Samples.FlowTemplates.LlmRouter,
    Blackboex.Samples.FlowTemplates.ApprovalWithTimeout,
    Blackboex.Samples.FlowTemplates.SagaCompensation,
    Blackboex.Samples.FlowTemplates.NotificationFanout,
    Blackboex.Samples.FlowTemplates.SlaMonitor,
    Blackboex.Samples.FlowTemplates.AsyncJobPoller,
    Blackboex.Samples.FlowTemplates.GithubCiResponder,
    Blackboex.Samples.FlowTemplates.SubFlowOrchestrator
  ]

  @spec echo_transform() :: map()
  def echo_transform do
    id = "echo_transform"

    %{
      kind: :flow,
      id: id,
      sample_uuid: Id.uuid(:flow, id),
      name: "Echo Transform",
      description: "Simple active flow used by playground samples to demonstrate internal calls.",
      category: "Getting Started",
      icon: "hero-arrow-path",
      position: length(@template_modules),
      definition: %{
        "version" => "1.0",
        "nodes" => [
          %{
            "id" => "n1",
            "type" => "start",
            "position" => %{"x" => 80, "y" => 200},
            "data" => %{
              "name" => "Start",
              "payload_schema" => [
                %{"name" => "message", "type" => "string", "required" => false},
                %{"name" => "items", "type" => "array", "required" => false}
              ]
            }
          },
          %{
            "id" => "n2",
            "type" => "elixir_code",
            "position" => %{"x" => 300, "y" => 200},
            "data" => %{
              "name" => "Transform",
              "code" => ~S"""
              message = input["message"] || "no message"
              items = input["items"]

              result =
                if is_list(items) do
                  processed =
                    Enum.map(items, fn item ->
                      if is_map(item), do: Map.put(item, "processed", true), else: %{"value" => item, "processed" => true}
                    end)

                  %{"message" => message, "items" => processed, "count" => length(processed)}
                else
                  %{"echo" => message, "timestamp" => DateTime.to_string(DateTime.utc_now())}
                end

              {result, Map.put(state, "result", inspect(result))}
              """
            }
          },
          %{
            "id" => "n3",
            "type" => "end",
            "position" => %{"x" => 550, "y" => 200},
            "data" => %{"name" => "End"}
          }
        ],
        "edges" => [
          %{
            "id" => "e1",
            "source" => "n1",
            "source_port" => 0,
            "target" => "n2",
            "target_port" => 0
          },
          %{
            "id" => "e2",
            "source" => "n2",
            "source_port" => 0,
            "target" => "n3",
            "target_port" => 0
          }
        ]
      }
    }
  end

  @spec list() :: [map()]
  def list do
    templates =
      @template_modules
      |> Enum.map(& &1.template())
      |> Enum.with_index()
      |> Enum.map(fn {template, index} ->
        template
        |> Map.put(:kind, :flow)
        |> Map.put(:sample_uuid, Id.uuid(:flow, template.id))
        |> Map.put(:position, index)
      end)

    templates ++ [echo_transform()]
  end
end
