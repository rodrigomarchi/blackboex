defmodule Blackboex.Samples.ApiTemplates.SlackEventHandler do
  @moduledoc """
  Template: Slack Event Handler

  Receives slash commands and Slack events, handles URL verification
  challenge, and returns appropriate responses.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "slack-event-handler",
      name: "Slack Event Handler",
      description: "Recebe slash commands e eventos do Slack com suporte a URL verification",
      category: "Webhooks",
      template_type: "webhook",
      icon: "message-square",
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
        "challenge" => "string",
        "text" => "string",
        "user_id" => "string"
      },
      example_request: %{
        "type" => "slash_command",
        "text" => "hello world",
        "user_id" => "U012AB3CD",
        "channel_id" => "C012AB3CD",
        "command" => "/mycommand"
      },
      example_response: %{
        "response_type" => "in_channel",
        "text" => "Hello from your API! You said: hello world"
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
          %{"name" => "url_verification challenge returns challenge", "status" => "pass"},
          %{"name" => "slash_command returns in_channel response", "status" => "pass"},
          %{"name" => "event_callback returns ok", "status" => "pass"},
          %{"name" => "missing type returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Slack Event Handler."

      alias Request
      alias Helpers

      @doc "Processes a Slack event or slash command and returns a response map."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          Helpers.build_response(data)
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
      @moduledoc "Helper functions for Slack Event handler."

      @doc "Builds the appropriate response map based on the Slack event type."
      @spec build_response(map()) :: map()
      def build_response(%{type: "url_verification"} = data) do
        %{challenge: data.challenge}
      end

      def build_response(%{type: "slash_command"} = data) do
        text = data.text || ""

        %{
          response_type: "in_channel",
          text: "Hello from your API! You said: #{text}"
        }
      end

      def build_response(%{type: "event_callback"}) do
        %{ok: true}
      end

      def build_response(%{type: type}) do
        %{ok: true, type: type}
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for Slack Event handler."

      use Blackboex.Schema
      import Ecto.Changeset

      @primary_key false
      embedded_schema do
        field :type, :string
        field :challenge, :string
        field :text, :string
        field :user_id, :string
        field :channel_id, :string
        field :command, :string
      end

      @doc "Casts and validates Slack event params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:type, :challenge, :text, :user_id, :channel_id, :command])
        |> validate_required([:type])
        |> validate_length(:type, min: 1, max: 100)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema for Slack Event handler — documents output structure."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :response_type, :string
        field :text, :string
        field :challenge, :string
        field :ok, :boolean
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case

      test "url_verification challenge returns challenge value" do
        params = %{"type" => "url_verification", "challenge" => "abc123xyz"}
        result = Handler.handle(params)
        assert result.challenge == "abc123xyz"
      end

      test "slash_command returns in_channel response with text" do
        params = %{
          "type" => "slash_command",
          "text" => "hello world",
          "user_id" => "U012AB3CD",
          "channel_id" => "C012AB3CD",
          "command" => "/mycommand"
        }

        result = Handler.handle(params)
        assert result.response_type == "in_channel"
        assert String.contains?(result.text, "hello world")
      end

      test "event_callback returns ok" do
        params = %{"type" => "event_callback", "event" => %{"type" => "message"}}
        result = Handler.handle(params)
        assert result.ok == true
      end

      test "missing type returns error" do
        result = Handler.handle(%{})
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :type)
      end

      test "Request.changeset/1 is valid with required fields" do
        cs = Request.changeset(%{"type" => "slash_command"})
        assert cs.valid?
      end

      test "Request.changeset/1 is invalid when type is missing" do
        cs = Request.changeset(%{})
        refute cs.valid?
      end
    end
    """
  end

  defp readme_content do
    """
    # Slack Event Handler

    Recebe slash commands e eventos do Slack. Suporta URL verification challenge
    para configuração do endpoint no Slack App Dashboard.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `type` | string | sim | Tipo: `url_verification`, `slash_command`, `event_callback` |
    | `challenge` | string | não | Token de verificação (apenas para `url_verification`) |
    | `text` | string | não | Texto do slash command |
    | `user_id` | string | não | ID do usuário Slack |
    | `channel_id` | string | não | ID do canal |
    | `command` | string | não | Comando slash (ex: `/mycommand`) |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/slack-event-handler \\
      -H "Content-Type: application/json" \\
      -d '{
        "type": "slash_command",
        "text": "hello world",
        "user_id": "U012AB3CD",
        "command": "/mycommand"
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "response_type": "in_channel",
      "text": "Hello from your API! You said: hello world"
    }
    ```

    ## URL Verification

    Ao configurar o endpoint no Slack, responda ao challenge:

    ```json
    {"type": "url_verification", "challenge": "abc123xyz"}
    ```

    Resposta: `{"challenge": "abc123xyz"}`
    """
  end
end
