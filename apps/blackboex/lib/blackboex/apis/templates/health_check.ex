defmodule Blackboex.Apis.Templates.HealthCheck do
  @moduledoc """
  Template: Health Check API

  Status endpoint with version, uptime and dependency checks.
  """

  @spec template() :: Blackboex.Apis.Templates.template()
  def template do
    %{
      id: "health-check",
      name: "Health Check API",
      description: "Status endpoint com versão, uptime e verificação de dependências",
      category: "Protótipos",
      icon: "heart",
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
        "include_details" => "boolean"
      },
      example_request: %{
        "include_details" => true
      },
      example_response: %{
        "status" => "ok",
        "version" => "1.0.0",
        "uptime_seconds" => 86_400,
        "checks" => %{
          "database" => "ok",
          "cache" => "ok",
          "external_api" => "ok"
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
          %{"name" => "returns status ok", "status" => "pass"},
          %{"name" => "returns version string", "status" => "pass"},
          %{"name" => "returns uptime_seconds as integer", "status" => "pass"},
          %{"name" => "include_details true returns checks map", "status" => "pass"},
          %{"name" => "include_details false omits checks", "status" => "pass"},
          %{"name" => "no params defaults include_details to false", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Handler for health check endpoint."

      @doc "Processes a health check request and returns status information."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)

          base = %{
            status: "ok",
            version: Helpers.version(),
            uptime_seconds: Helpers.uptime_seconds()
          }

          if data.include_details do
            Map.put(base, :checks, Helpers.dependency_checks())
          else
            base
          end
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
      @moduledoc "Helper functions providing version, uptime and dependency check data."

      @version "1.0.0"

      @doc "Returns the current application version string."
      @spec version() :: String.t()
      def version, do: @version

      @doc "Returns simulated uptime in seconds."
      @spec uptime_seconds() :: integer()
      def uptime_seconds do
        # uptime is simulated in sandbox context
        0
      end

      @doc "Returns a map of simulated dependency health checks."
      @spec dependency_checks() :: map()
      def dependency_checks do
        %{
          database: check_database(),
          cache: check_cache(),
          external_api: check_external_api()
        }
      end

      # Simulated checks — replace with real connectivity tests
      defp check_database, do: "ok"
      defp check_cache, do: "ok"
      defp check_external_api, do: "ok"
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Request schema for health check endpoint."

      use Blackboex.Schema
      import Ecto.Changeset

      @primary_key false
      embedded_schema do
        field :include_details, :boolean
      end

      @doc "Casts and validates health check request params."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:include_details])
        |> set_default_include_details()
      end

      defp set_default_include_details(changeset) do
        if get_field(changeset, :include_details) == nil do
          put_change(changeset, :include_details, false)
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
      @moduledoc "Response schema documenting the health check output."

      use Blackboex.Schema

      @primary_key false
      embedded_schema do
        field :status, :string
        field :version, :string
        field :uptime_seconds, :integer
        field :checks, :map
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule HandlerTest do
      use ExUnit.Case, async: true

      describe "handle/1" do
        test "returns status ok" do
          result = Handler.handle(%{})
          assert result.status == "ok"
        end

        test "returns version string" do
          result = Handler.handle(%{})
          assert is_binary(result.version)
          assert String.match?(result.version, ~r/^\d+\.\d+\.\d+$/)
        end

        test "returns uptime_seconds as non-negative integer" do
          result = Handler.handle(%{})
          assert is_integer(result.uptime_seconds)
          assert result.uptime_seconds >= 0
        end

        test "include_details true returns checks map" do
          result = Handler.handle(%{"include_details" => true})
          assert is_map(result.checks)
          assert Map.has_key?(result.checks, :database)
          assert Map.has_key?(result.checks, :cache)
        end

        test "include_details false omits checks" do
          result = Handler.handle(%{"include_details" => false})
          refute Map.has_key?(result, :checks)
        end

        test "no params defaults include_details to false" do
          result = Handler.handle(%{})
          refute Map.has_key?(result, :checks)
        end
      end

      test "Request.changeset defaults include_details to false" do
        cs = Request.changeset(%{})
        assert cs.valid?
        assert Ecto.Changeset.get_change(cs, :include_details) == false
      end
    end
    """
  end

  defp readme_content do
    """
    # Health Check API

    Endpoint de status para monitoramento de saúde da aplicação. Retorna
    versão, uptime e verificações de dependências (banco, cache, APIs externas).

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Padrão | Descrição |
    |-------|------|-------------|--------|-----------|
    | `include_details` | boolean | não | false | Se deve incluir checks de dependências |

    ## Exemplo de Requisição

    ```bash
    # Status básico
    curl -X POST https://api.blackboex.com/api/minha-org/health-check \\
      -H "Content-Type: application/json" \\
      -d '{}'

    # Com detalhes das dependências
    curl -X POST https://api.blackboex.com/api/minha-org/health-check \\
      -H "Content-Type: application/json" \\
      -d '{"include_details": true}'
    ```

    ## Exemplo de Resposta (com detalhes)

    ```json
    {
      "status": "ok",
      "version": "1.0.0",
      "uptime_seconds": 86400,
      "checks": {
        "database": "ok",
        "cache": "ok",
        "external_api": "ok"
      }
    }
    ```

    ## Personalização

    Substitua os métodos `check_database/0`, `check_cache/0` e `check_external_api/0`
    no módulo `Helpers` por verificações reais de conectividade.

    ## Casos de Uso

    - Endpoint de readiness/liveness para Kubernetes
    - Monitoramento com Datadog, New Relic ou Grafana
    - Status page pública da aplicação
    """
  end
end
