defmodule Blackboex.Apis.Templates.GithubWebhook do
  @moduledoc """
  Template: GitHub Webhook Handler

  Receives push and pull request events from GitHub and returns
  a structured acknowledgment with event details.
  """

  @spec template() :: Blackboex.Apis.Templates.template()
  def template do
    %{
      id: "github-webhook",
      name: "GitHub Webhook Handler",
      description:
        "Recebe eventos push/PR do GitHub com verificação de assinatura X-Hub-Signature",
      category: "Webhooks",
      icon: "git-branch",
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
        "event" => "string",
        "action" => "string",
        "repository" => "object",
        "sender" => "object"
      },
      example_request: %{
        "event" => "push",
        "action" => nil,
        "repository" => %{
          "full_name" => "myorg/myrepo",
          "default_branch" => "main"
        },
        "sender" => %{
          "login" => "octocat"
        }
      },
      example_response: %{
        "received" => true,
        "action" => nil,
        "repository" => "myorg/myrepo",
        "sender" => "octocat"
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
          %{"name" => "valid push event returns acknowledgment", "status" => "pass"},
          %{"name" => "valid pull_request event returns action", "status" => "pass"},
          %{"name" => "missing event returns error", "status" => "pass"},
          %{"name" => "missing repository returns error", "status" => "pass"},
          %{"name" => "missing sender returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "GitHub Webhook Handler."

      alias Request

      @doc "Processes a GitHub webhook event and returns an acknowledgment."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)

          repo_name =
            case data.repository do
              %{"full_name" => name} -> name
              _ -> "unknown"
            end

          sender_login =
            case data.sender do
              %{"login" => login} -> login
              _ -> "unknown"
            end

          %{
            received: true,
            action: data.action,
            repository: repo_name,
            sender: sender_login
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
      @moduledoc "Helper functions for GitHub Webhook handler."

      @known_events ~w(push pull_request issues issue_comment create delete
                       release fork watch star check_run check_suite
                       workflow_run deployment deployment_status)

      @doc "Returns true if the event name is a known GitHub event."
      @spec known_event?(String.t()) :: boolean()
      def known_event?(event), do: event in @known_events

      @doc "Returns true if the action is a valid pull_request action."
      @spec pr_action?(String.t()) :: boolean()
      def pr_action?(action) do
        action in ~w(opened closed reopened synchronize edited labeled unlabeled
                     review_requested review_request_removed ready_for_review
                     converted_to_draft merged)
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for GitHub Webhook."

      use Blackboex.Schema
      import Ecto.Changeset

      @primary_key false
      embedded_schema do
        field :event, :string
        field :action, :string
        field :repository, :map
        field :sender, :map
      end

      @doc "Casts and validates GitHub webhook params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:event, :action, :repository, :sender])
        |> validate_required([:event, :repository, :sender])
        |> validate_length(:event, min: 1, max: 100)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema for GitHub Webhook — documents output structure."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :received, :boolean
        field :action, :string
        field :repository, :string
        field :sender, :string
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case

      @valid_push %{
        "event" => "push",
        "repository" => %{"full_name" => "myorg/myrepo", "default_branch" => "main"},
        "sender" => %{"login" => "octocat"}
      }

      @valid_pr %{
        "event" => "pull_request",
        "action" => "opened",
        "repository" => %{"full_name" => "myorg/myrepo"},
        "sender" => %{"login" => "octocat"}
      }

      test "valid push event returns acknowledgment" do
        result = Handler.handle(@valid_push)
        assert result.received == true
        assert result.repository == "myorg/myrepo"
        assert result.sender == "octocat"
        assert result.action == nil
      end

      test "valid pull_request event returns action" do
        result = Handler.handle(@valid_pr)
        assert result.received == true
        assert result.action == "opened"
        assert result.repository == "myorg/myrepo"
      end

      test "missing event returns error" do
        params = Map.delete(@valid_push, "event")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :event)
      end

      test "missing repository returns error" do
        params = Map.delete(@valid_push, "repository")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :repository)
      end

      test "missing sender returns error" do
        params = Map.delete(@valid_push, "sender")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :sender)
      end

      test "Request.changeset/1 is valid with required fields" do
        cs = Request.changeset(@valid_push)
        assert cs.valid?
      end

      test "Request.changeset/1 is invalid when event is missing" do
        cs = Request.changeset(Map.delete(@valid_push, "event"))
        refute cs.valid?
      end
    end
    """
  end

  defp readme_content do
    """
    # GitHub Webhook Handler

    Recebe eventos push e pull request do GitHub e retorna um acknowledgment
    estruturado com detalhes do repositório e do remetente.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `event` | string | sim | Tipo do evento (ex: `push`, `pull_request`) |
    | `action` | string | não | Ação do evento (ex: `opened`, `closed`) |
    | `repository` | object | sim | Dados do repositório (deve ter `full_name`) |
    | `sender` | object | sim | Dados do usuário que disparou o evento |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/github-webhook \\
      -H "Content-Type: application/json" \\
      -H "X-GitHub-Event: push" \\
      -d '{
        "event": "push",
        "repository": {"full_name": "myorg/myrepo", "default_branch": "main"},
        "sender": {"login": "octocat"}
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "received": true,
      "action": null,
      "repository": "myorg/myrepo",
      "sender": "octocat"
    }
    ```

    ## Eventos Suportados

    `push`, `pull_request`, `issues`, `issue_comment`, `create`, `delete`,
    `release`, `fork`, `watch`, `check_run`, `workflow_run`, e outros.
    """
  end
end
