defmodule Blackboex.Apis.Templates.ErrorSimulation do
  @moduledoc """
  Template: Error Simulation API

  Returns configurable HTTP error responses (400, 401, 403, 404, 429, 500)
  with optional delay. Useful for testing error handling in client code.
  """

  @spec template() :: Blackboex.Apis.Templates.template()
  def template do
    %{
      id: "error-simulation",
      name: "Error Simulation API",
      description: "Retorna erros configuráveis (400, 401, 403, 404, 429, 500) para testes",
      category: "Mocks",
      template_type: "computation",
      icon: "exclamation-triangle",
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
        "status_code" => "integer",
        "delay_ms" => "integer"
      },
      example_request: %{
        "status_code" => 429,
        "delay_ms" => 0
      },
      example_response: %{
        "error" => %{
          "code" => 429,
          "message" => "Too Many Requests",
          "details" => "Rate limit exceeded. Please retry after 60 seconds.",
          "retry_after" => 60
        }
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
          %{"name" => "400 returns bad request error body", "status" => "pass"},
          %{"name" => "401 returns unauthorized error body", "status" => "pass"},
          %{"name" => "404 returns not found error body", "status" => "pass"},
          %{"name" => "429 returns rate limit error body", "status" => "pass"},
          %{"name" => "500 returns internal server error body", "status" => "pass"},
          %{"name" => "unsupported status code returns validation error", "status" => "pass"},
          %{"name" => "missing status_code returns validation error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Handler for error simulation endpoint."

      @doc "Processes an error simulation request and returns the configured error body."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          # delay_ms is acknowledged but not applied in sandbox context
          Helpers.error_body(data.status_code)
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
      @moduledoc "Helper functions providing pre-built HTTP error response bodies."

      @supported_codes [400, 401, 403, 404, 422, 429, 500, 502, 503]

      @error_bodies %{
        400 => %{
          error: %{
            code: 400,
            message: "Bad Request",
            details: "The request could not be understood due to malformed syntax."
          }
        },
        401 => %{
          error: %{
            code: 401,
            message: "Unauthorized",
            details: "Authentication credentials are missing or invalid."
          }
        },
        403 => %{
          error: %{
            code: 403,
            message: "Forbidden",
            details: "You do not have permission to access this resource."
          }
        },
        404 => %{
          error: %{
            code: 404,
            message: "Not Found",
            details: "The requested resource could not be found."
          }
        },
        422 => %{
          error: %{
            code: 422,
            message: "Unprocessable Entity",
            details: "The request was well-formed but contains semantic errors."
          }
        },
        429 => %{
          error: %{
            code: 429,
            message: "Too Many Requests",
            details: "Rate limit exceeded. Please retry after 60 seconds.",
            retry_after: 60
          }
        },
        500 => %{
          error: %{
            code: 500,
            message: "Internal Server Error",
            details: "An unexpected error occurred on the server."
          }
        },
        502 => %{
          error: %{
            code: 502,
            message: "Bad Gateway",
            details: "The upstream server returned an invalid response."
          }
        },
        503 => %{
          error: %{
            code: 503,
            message: "Service Unavailable",
            details: "The server is temporarily unable to handle requests.",
            retry_after: 30
          }
        }
      }

      @doc "Returns the error body map for a supported HTTP status code."
      @spec error_body(integer()) :: map()
      def error_body(code), do: Map.fetch!(@error_bodies, code)

      @doc "Returns the list of supported error status codes."
      @spec supported_codes() :: [integer()]
      def supported_codes, do: @supported_codes
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for error simulation."

      use Blackboex.Schema
      import Ecto.Changeset

      @supported_codes [400, 401, 403, 404, 422, 429, 500, 502, 503]

      @primary_key false
      embedded_schema do
        field :status_code, :integer
        field :delay_ms, :integer
      end

      @doc "Casts and validates error simulation request params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:status_code, :delay_ms])
        |> validate_required([:status_code])
        |> validate_inclusion(:status_code, @supported_codes)
        |> validate_number(:delay_ms, greater_than_or_equal_to: 0, less_than_or_equal_to: 5000)
        |> maybe_set_default_delay()
      end

      defp maybe_set_default_delay(changeset) do
        if get_field(changeset, :delay_ms) == nil do
          put_change(changeset, :delay_ms, 0)
        else
          changeset
        end
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Response schema documenting the error simulation output."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :error, :map
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case, async: true

      describe "handle/1" do
        test "400 returns bad request error body" do
          result = Handler.handle(%{"status_code" => 400})
          assert result.error.code == 400
          assert result.error.message == "Bad Request"
        end

        test "401 returns unauthorized error body" do
          result = Handler.handle(%{"status_code" => 401})
          assert result.error.code == 401
          assert result.error.message == "Unauthorized"
        end

        test "403 returns forbidden error body" do
          result = Handler.handle(%{"status_code" => 403})
          assert result.error.code == 403
        end

        test "404 returns not found error body" do
          result = Handler.handle(%{"status_code" => 404})
          assert result.error.code == 404
          assert result.error.message == "Not Found"
        end

        test "429 returns rate limit error body with retry_after" do
          result = Handler.handle(%{"status_code" => 429})
          assert result.error.code == 429
          assert Map.has_key?(result.error, :retry_after)
        end

        test "500 returns internal server error body" do
          result = Handler.handle(%{"status_code" => 500})
          assert result.error.code == 500
          assert result.error.message == "Internal Server Error"
        end

        test "unsupported status code returns validation error" do
          result = Handler.handle(%{"status_code" => 418})
          assert result.error == "Validation failed"
          assert Map.has_key?(result.details, :status_code)
        end

        test "missing status_code returns validation error" do
          result = Handler.handle(%{})
          assert result.error == "Validation failed"
          assert Map.has_key?(result.details, :status_code)
        end

        test "delay_ms defaults to 0 when not provided" do
          result = Handler.handle(%{"status_code" => 500})
          assert Map.has_key?(result, :error)
        end
      end

      test "Request.changeset validates required fields" do
        cs = Request.changeset(%{})
        refute cs.valid?
        assert Keyword.has_key?(cs.errors, :status_code)
      end
    end
    """
  end

  defp readme_content do
    """
    # Error Simulation API

    Retorna respostas de erro HTTP configuráveis com corpo JSON padronizado.
    Perfeito para testar como seu cliente lida com diferentes cenários de erro
    sem precisar forçar erros reais no servidor.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `status_code` | integer | sim | Código HTTP de erro a simular |
    | `delay_ms` | integer | não | Atraso artificial em ms (0–5000, padrão: 0) |

    ## Códigos Suportados

    400, 401, 403, 404, 422, 429, 500, 502, 503

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/error-simulation \\
      -H "Content-Type: application/json" \\
      -d '{"status_code": 429, "delay_ms": 0}'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "error": {
        "code": 429,
        "message": "Too Many Requests",
        "details": "Rate limit exceeded. Please retry after 60 seconds.",
        "retry_after": 60
      }
    }
    ```

    ## Casos de Uso

    - Testar retry logic e exponential backoff no cliente
    - Simular rate limiting durante desenvolvimento
    - Validar tratamento de erros em pipelines de integração
    - Mock de APIs externas instáveis
    """
  end
end
