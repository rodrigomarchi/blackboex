defmodule Blackboex.Samples.ApiTemplates.OauthCallback do
  @moduledoc """
  Template: OAuth Callback Handler

  Receives OAuth2 authorization code callback and returns a mock
  access token response following the OAuth2 spec.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "oauth-callback",
      name: "OAuth Callback Handler",
      description: "Recebe callback OAuth2 com código de autorização e retorna token mock",
      category: "Webhooks",
      template_type: "webhook",
      icon: "key",
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
        "code" => "string",
        "state" => "string",
        "redirect_uri" => "string"
      },
      example_request: %{
        "code" => "4/P7q7W91a-oMsCeLvIaQm6bTrgtp7",
        "state" => "abc123security",
        "redirect_uri" => "https://myapp.com/callback"
      },
      example_response: %{
        "access_token" => "ya29.mock_access_token_abc123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "refresh_token" => "1//mock_refresh_token_xyz789",
        "scope" => "openid email profile"
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
          %{"name" => "valid code returns token response", "status" => "pass"},
          %{"name" => "missing code returns error", "status" => "pass"},
          %{"name" => "missing redirect_uri returns error", "status" => "pass"},
          %{"name" => "token response has required fields", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "OAuth Callback Handler."

      alias Request
      alias Helpers

      @doc "Processes an OAuth2 callback and returns a mock token response."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          Helpers.generate_mock_token(data.code)
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
      @moduledoc "Helper functions for OAuth Callback handler."

      @token_prefix "ya29.mock_"
      @refresh_prefix "1//mock_refresh_"

      @doc "Generates a deterministic mock OAuth2 token from the authorization code."
      @spec generate_mock_token(String.t()) :: map()
      def generate_mock_token(code) do
        code_hash =
          code
          |> String.to_charlist()
          |> Enum.reduce(0, fn c, acc -> rem(acc * 31 + c, 0xFFFFFFFF) end)
          |> Integer.to_string(16)
          |> String.downcase()

        %{
          access_token: "#{@token_prefix}#{code_hash}",
          token_type: "Bearer",
          expires_in: 3600,
          refresh_token: "#{@refresh_prefix}#{code_hash}",
          scope: "openid email profile"
        }
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for OAuth Callback handler."

      use Blackboex.Schema
      import Ecto.Changeset

      @primary_key false
      embedded_schema do
        field :code, :string
        field :state, :string
        field :redirect_uri, :string
      end

      @doc "Casts and validates OAuth2 callback params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:code, :state, :redirect_uri])
        |> validate_required([:code, :redirect_uri])
        |> validate_length(:code, min: 1, max: 500)
        |> validate_length(:redirect_uri, min: 1, max: 2000)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema for OAuth Callback handler — documents output structure."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :access_token, :string
        field :token_type, :string
        field :expires_in, :integer
        field :refresh_token, :string
        field :scope, :string
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case

      @valid_params %{
        "code" => "4/P7q7W91a-oMsCeLvIaQm6bTrgtp7",
        "state" => "abc123security",
        "redirect_uri" => "https://myapp.com/callback"
      }

      test "valid code returns token response" do
        result = Handler.handle(@valid_params)
        assert is_binary(result.access_token)
        assert result.token_type == "Bearer"
        assert is_integer(result.expires_in)
        assert result.expires_in > 0
        assert is_binary(result.refresh_token)
        assert is_binary(result.scope)
      end

      test "token response has required OAuth2 fields" do
        result = Handler.handle(@valid_params)
        assert Map.has_key?(result, :access_token)
        assert Map.has_key?(result, :token_type)
        assert Map.has_key?(result, :expires_in)
        assert Map.has_key?(result, :refresh_token)
      end

      test "missing code returns error" do
        params = Map.delete(@valid_params, "code")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :code)
      end

      test "missing redirect_uri returns error" do
        params = Map.delete(@valid_params, "redirect_uri")
        result = Handler.handle(params)
        assert result.error == "Validation failed"
        assert Map.has_key?(result.details, :redirect_uri)
      end

      test "Request.changeset/1 is valid with required fields" do
        cs = Request.changeset(@valid_params)
        assert cs.valid?
      end

      test "Request.changeset/1 is invalid when code is missing" do
        cs = Request.changeset(Map.delete(@valid_params, "code"))
        refute cs.valid?
      end
    end
    """
  end

  defp readme_content do
    """
    # OAuth Callback Handler

    Recebe o callback OAuth2 com o código de autorização e retorna um token
    de acesso mock seguindo o padrão OAuth2/OpenID Connect.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `code` | string | sim | Código de autorização OAuth2 |
    | `redirect_uri` | string | sim | URI de redirecionamento registrada |
    | `state` | string | não | Parâmetro de segurança anti-CSRF |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/oauth-callback \\
      -H "Content-Type: application/json" \\
      -d '{
        "code": "4/P7q7W91a-oMsCeLvIaQm6bTrgtp7",
        "state": "abc123security",
        "redirect_uri": "https://myapp.com/callback"
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "access_token": "ya29.mock_access_token_abc123",
      "token_type": "Bearer",
      "expires_in": 3600,
      "refresh_token": "1//mock_refresh_token_xyz789",
      "scope": "openid email profile"
    }
    ```

    ## Notas

    - O token retornado é um **mock determinístico** derivado do código de autorização
    - Use para desenvolvimento/testes de fluxos OAuth2 sem servidor de autorização real
    - Em produção, substitua `Helpers.generate_mock_token/1` pela chamada real ao provider
    """
  end
end
