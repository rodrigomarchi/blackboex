defmodule Blackboex.Samples.ApiTemplates.NotificationMock do
  @moduledoc """
  Template: SMS/Email Notification Mock

  Simulates sending notifications via SMS, email, or push channels
  without connecting to real delivery services.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "notification-mock",
      name: "SMS/Email Notification Mock",
      description: "Simula envio de notificação multi-canal (SMS, email, push) para testes",
      category: "Mocks",
      template_type: "computation",
      icon: "bell",
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
        "channel" => "string",
        "recipient" => "string",
        "message" => "string"
      },
      example_request: %{
        "channel" => "email",
        "recipient" => "user@example.com",
        "message" => "Your verification code is 123456"
      },
      example_response: %{
        "sent" => true,
        "message_id" => "msg_mock_a1b2c3d4",
        "channel" => "email"
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
          %{"name" => "email channel returns sent confirmation", "status" => "pass"},
          %{"name" => "sms channel returns sent confirmation", "status" => "pass"},
          %{"name" => "push channel returns sent confirmation", "status" => "pass"},
          %{"name" => "invalid channel returns validation error", "status" => "pass"},
          %{"name" => "missing recipient returns validation error", "status" => "pass"},
          %{"name" => "missing message returns validation error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Handler for SMS/Email notification mock endpoint."

      @doc "Processes a notification send request and returns a mock confirmation."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          message_id = Helpers.generate_message_id(data.recipient)

          %{
            sent: true,
            message_id: message_id,
            channel: data.channel
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
      @moduledoc "Helper functions for notification mock."

      @doc "Generates a deterministic mock message ID from recipient."
      @spec generate_message_id(String.t()) :: String.t()
      def generate_message_id(recipient) do
        ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

        hash =
          (recipient <> Integer.to_string(ts))
          |> String.to_charlist()
          |> Enum.reduce(0, fn c, acc -> rem(acc * 31 + c, 0xFFFFFFFF) end)
          |> Integer.to_string(16)
          |> String.downcase()

        "msg_mock_#{hash}"
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for notification mock."

      use Blackboex.Schema
      import Ecto.Changeset

      @valid_channels ~w(email sms push whatsapp)

      @primary_key false
      embedded_schema do
        field :channel, :string
        field :recipient, :string
        field :message, :string
        field :subject, :string
      end

      @doc "Casts and validates notification request params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:channel, :recipient, :message, :subject])
        |> validate_required([:channel, :recipient, :message])
        |> validate_inclusion(:channel, @valid_channels,
          message: "must be one of: #{Enum.join(@valid_channels, ", ")}"
        )
        |> validate_length(:recipient, min: 1, max: 500)
        |> validate_length(:message, min: 1, max: 5000)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema documenting the notification mock output."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :sent, :boolean
        field :message_id, :string
        field :channel, :string
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case, async: true

      test "email channel returns sent confirmation" do
        result = Handler.handle(%{"channel" => "email", "recipient" => "user@example.com", "message" => "Test"})
        assert result.sent == true
        assert result.channel == "email"
        assert String.starts_with?(result.message_id, "msg_mock_")
      end

      test "sms channel returns sent confirmation" do
        result = Handler.handle(%{"channel" => "sms", "recipient" => "+5511999999999", "message" => "Test SMS"})
        assert result.sent == true
        assert result.channel == "sms"
      end

      test "push channel returns sent confirmation" do
        result = Handler.handle(%{
          "channel" => "push",
          "recipient" => "device_token_abc",
          "message" => "Push notification"
        })
        assert result.sent == true
        assert result.channel == "push"
      end

      test "invalid channel returns validation error" do
        result = Handler.handle(%{"channel" => "fax", "recipient" => "user@example.com", "message" => "Test"})
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :channel)
      end

      test "missing recipient returns validation error" do
        result = Handler.handle(%{"channel" => "email", "message" => "Test"})
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :recipient)
      end

      test "missing message returns validation error" do
        result = Handler.handle(%{"channel" => "email", "recipient" => "user@example.com"})
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :message)
      end

      test "Request.changeset validates required fields" do
        cs = Request.changeset(%{})
        refute cs.valid?
        assert Keyword.has_key?(cs.errors, :channel)
        assert Keyword.has_key?(cs.errors, :recipient)
        assert Keyword.has_key?(cs.errors, :message)
      end
    end
    """
  end

  defp readme_content do
    """
    # SMS/Email Notification Mock

    Simula envio de notificações por múltiplos canais sem conectar a serviços reais.
    Ideal para testar fluxos de notificação em desenvolvimento e CI/CD.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `channel` | string | sim | Canal: `email`, `sms`, `push`, `whatsapp` |
    | `recipient` | string | sim | Destinatário (email, telefone ou device token) |
    | `message` | string | sim | Conteúdo da mensagem |
    | `subject` | string | não | Assunto (apenas para email) |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/notification-mock \\
      -H "Content-Type: application/json" \\
      -d '{
        "channel": "email",
        "recipient": "user@example.com",
        "message": "Your verification code is 123456"
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "sent": true,
      "message_id": "msg_mock_a1b2c3d4",
      "channel": "email"
    }
    ```

    ## Canais Suportados

    | Canal | Formato do `recipient` |
    |-------|----------------------|
    | `email` | Endereço de email |
    | `sms` | Número de telefone |
    | `push` | Device token |
    | `whatsapp` | Número de telefone |
    """
  end
end
