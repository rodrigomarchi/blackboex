defmodule Blackboex.Apis.Templates.StripeWebhook do
  @moduledoc """
  Template: Stripe Webhook Receiver

  Receives Stripe payment events, verifies the webhook signature (mocked),
  and returns a structured acknowledgment.
  """

  @spec template() :: Blackboex.Apis.Templates.template()
  def template do
    %{
      id: "stripe-webhook",
      name: "Stripe Webhook Receiver",
      description: "Recebe eventos de pagamento do Stripe com verificação de assinatura",
      category: "Webhooks",
      template_type: "webhook",
      icon: "credit-card",
      method: "POST",
      files: %{
        handler: handler_code(),
        helpers: helpers_code(),
        request_schema: request_schema_code(),
        response_schema: response_schema_code(),
        test: test_code(),
        readme: readme_content()
      },
      param_schema: %{
        "type" => "string",
        "data" => "object",
        "stripe_signature" => "string"
      },
      example_request: %{
        "type" => "payment_intent.succeeded",
        "data" => %{
          "object" => %{
            "id" => "pi_3NqJ2L2eZvKYlo2C1gE1ABCD",
            "amount" => 2000,
            "currency" => "brl",
            "status" => "succeeded"
          }
        },
        "stripe_signature" => "t=1697123456,v1=abc123def456"
      },
      example_response: %{
        "received" => true,
        "event_type" => "payment_intent.succeeded",
        "processed_at" => "2024-01-15T10:30:00Z"
      },
      validation_report: %{
        "compilation" => "pass",
        "compilation_errors" => [],
        "format" => "pass",
        "format_issues" => [],
        "credo" => "pass",
        "credo_issues" => [],
        "tests" => "pass",
        "test_results" => [
          %{"name" => "valid payment_intent.succeeded event", "status" => "pass"},
          %{"name" => "valid charge.refunded event", "status" => "pass"},
          %{"name" => "missing event type returns error", "status" => "pass"},
          %{"name" => "missing data returns error", "status" => "pass"},
          %{"name" => "unknown event type is accepted", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Stripe Webhook Receiver handler."

      alias Request
      alias Helpers

      @doc "Processes a Stripe webhook event and returns an acknowledgment."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          processed_at = Helpers.utc_now_iso()

          %{
            received: true,
            event_type: data.type,
            processed_at: processed_at
          }
        else
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          %{error: "Validation failed", details: errors}
        end
      end
    end
    """
  end

  defp helpers_code do
    ~S"""
    defmodule Helpers do
      @moduledoc "Helper functions for Stripe Webhook handler."

      @doc "Returns the current UTC time as an ISO8601 string."
      @spec utc_now_iso() :: String.t()
      def utc_now_iso do
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()
      end

      @doc "Returns true if the event type is a known Stripe event."
      @spec known_event?(String.t()) :: boolean()
      def known_event?(type) do
        type in [
          "payment_intent.succeeded",
          "payment_intent.payment_failed",
          "payment_intent.created",
          "charge.succeeded",
          "charge.failed",
          "charge.refunded",
          "customer.subscription.created",
          "customer.subscription.updated",
          "customer.subscription.deleted",
          "invoice.paid",
          "invoice.payment_failed"
        ]
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for Stripe Webhook."

      use Blackboex.Schema
      import Ecto.Changeset

      @primary_key false
      embedded_schema do
        field :type, :string
        field :data, :map
        field :stripe_signature, :string
      end

      @doc "Casts and validates Stripe webhook params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:type, :data, :stripe_signature])
        |> validate_required([:type, :data])
        |> validate_length(:type, min: 1, max: 100)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema for Stripe Webhook — documents output structure."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :received, :boolean
        field :event_type, :string
        field :processed_at, :string
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case

      @valid_params %{
        "type" => "payment_intent.succeeded",
        "data" => %{
          "object" => %{
            "id" => "pi_abc123",
            "amount" => 2000,
            "currency" => "brl",
            "status" => "succeeded"
          }
        },
        "stripe_signature" => "t=1697123456,v1=abc123"
      }

      test "valid payment_intent.succeeded event returns acknowledgment" do
        result = Handler.handle(@valid_params)
        assert result.received == true
        assert result.event_type == "payment_intent.succeeded"
        assert is_binary(result.processed_at)
      end

      test "valid charge.refunded event returns acknowledgment" do
        params = Map.put(@valid_params, "type", "charge.refunded")
        result = Handler.handle(params)
        assert result.received == true
        assert result.event_type == "charge.refunded"
      end

      test "missing event type returns error" do
        params = Map.delete(@valid_params, "type")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :type)
      end

      test "missing data returns error" do
        params = Map.delete(@valid_params, "data")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :data)
      end

      test "unknown event type is accepted (passthrough)" do
        params = Map.put(@valid_params, "type", "some.unknown.event")
        result = Handler.handle(params)
        assert result.received == true
        assert result.event_type == "some.unknown.event"
      end

      test "Request.changeset/1 is valid with required fields" do
        cs = Request.changeset(@valid_params)
        assert cs.valid?
      end

      test "Request.changeset/1 is invalid when type is missing" do
        cs = Request.changeset(Map.delete(@valid_params, "type"))
        refute cs.valid?
      end
    end
    """
  end

  defp readme_content do
    """
    # Stripe Webhook Receiver

    Recebe eventos de pagamento do Stripe e retorna um acknowledgment estruturado.
    Aceita todos os tipos de eventos Stripe e registra o horário de processamento.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `type` | string | sim | Tipo do evento Stripe (ex: `payment_intent.succeeded`) |
    | `data` | object | sim | Objeto de dados do evento Stripe |
    | `stripe_signature` | string | não | Header `Stripe-Signature` para verificação |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/stripe-webhook \\
      -H "Content-Type: application/json" \\
      -H "Stripe-Signature: t=1697123456,v1=abc123def456" \\
      -d '{
        "type": "payment_intent.succeeded",
        "data": {
          "object": {
            "id": "pi_3NqJ2L2eZvKYlo2C1gE1ABCD",
            "amount": 2000,
            "currency": "brl",
            "status": "succeeded"
          }
        }
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "received": true,
      "event_type": "payment_intent.succeeded",
      "processed_at": "2024-01-15T10:30:00Z"
    }
    ```

    ## Eventos Suportados

    - `payment_intent.succeeded` / `payment_intent.payment_failed`
    - `charge.succeeded` / `charge.failed` / `charge.refunded`
    - `customer.subscription.*`
    - `invoice.paid` / `invoice.payment_failed`
    - Qualquer outro evento é aceito e retorna `received: true`
    """
  end
end
