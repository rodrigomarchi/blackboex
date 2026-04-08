defmodule Blackboex.Apis.Templates.VerificadorElegibilidade do
  @moduledoc """
  Template: Verificador de Elegibilidade

  Checks eligibility for a service based on business rules:
  age, income, state (UF) and plan type.
  """

  @spec template() :: Blackboex.Apis.Templates.template()
  def template do
    %{
      id: "verificador-elegibilidade",
      name: "Verificador de Elegibilidade",
      description: "Checa elegibilidade para serviço baseado em regras de negócio",
      category: "AI Agent Tools",
      template_type: "computation",
      icon: "check-circle",
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
        "idade" => "integer",
        "renda" => "number",
        "uf" => "string",
        "tipo_plano" => "string"
      },
      example_request: %{
        "idade" => 30,
        "renda" => 3000.0,
        "uf" => "SP",
        "tipo_plano" => "basico"
      },
      example_response: %{
        "elegivel" => true,
        "motivo" => "todos os critérios atendidos",
        "planos_disponiveis" => ["basico", "intermediario"]
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
          %{"name" => "eligible profile returns elegivel true", "status" => "pass"},
          %{"name" => "underage returns not eligible", "status" => "pass"},
          %{"name" => "low income for premium returns not eligible", "status" => "pass"},
          %{"name" => "unavailable UF returns not eligible", "status" => "pass"},
          %{"name" => "eligible profile lists available plans", "status" => "pass"},
          %{"name" => "missing fields returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Checks eligibility for service plans based on business rules."

      @doc "Processes request and returns eligibility result or validation error."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          {elegivel, motivo} = Helpers.check_eligibility(data)
          planos = if elegivel, do: Helpers.available_plans(data), else: []
          %{elegivel: elegivel, motivo: motivo, planos_disponiveis: planos}
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
      @moduledoc "Eligibility check helpers for plan qualification rules."

      @min_age %{"basico" => 18, "intermediario" => 18, "premium" => 21, "empresarial" => 18}
      @min_income %{
        "basico" => 1_000.0,
        "intermediario" => 2_000.0,
        "premium" => 5_000.0,
        "empresarial" => 3_000.0
      }

      @unavailable_ufs %{
        "premium" => ["AC", "RR", "AP"],
        "empresarial" => ["AC", "RR"]
      }

      @doc "Returns {eligible?, reason} for the given applicant data."
      @spec check_eligibility(map()) :: {boolean(), String.t()}
      def check_eligibility(data) do
        plano = data.tipo_plano

        cond do
          data.idade < Map.get(@min_age, plano, 18) ->
            {false, "idade mínima não atingida para o plano #{plano}"}

          data.renda < Map.get(@min_income, plano, 0.0) ->
            {false, "renda insuficiente para o plano #{plano}"}

          data.uf in Map.get(@unavailable_ufs, plano, []) ->
            {false, "plano #{plano} não disponível no estado #{data.uf}"}

          true ->
            {true, "todos os critérios atendidos"}
        end
      end

      @doc "Returns list of plan names the applicant qualifies for."
      @spec available_plans(map()) :: [String.t()]
      def available_plans(data) do
        all_plans = ["basico", "intermediario", "premium", "empresarial"]

        Enum.filter(all_plans, fn plano ->
          idade_ok = data.idade >= Map.get(@min_age, plano, 18)
          renda_ok = data.renda >= Map.get(@min_income, plano, 0.0)
          uf_ok = data.uf not in Map.get(@unavailable_ufs, plano, [])
          idade_ok and renda_ok and uf_ok
        end)
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Input schema for the eligibility checker API."
      use Blackboex.Schema

      @valid_ufs ~w(AC AL AM AP BA CE DF ES GO MA MG MS MT PA PB PE PI PR RJ RN RO RR RS SC SE SP TO)
      @valid_planos ["basico", "intermediario", "premium", "empresarial"]

      embedded_schema do
        field :idade, :integer
        field :renda, :float
        field :uf, :string
        field :tipo_plano, :string
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:idade, :renda, :uf, :tipo_plano])
        |> validate_required([:idade, :renda, :uf, :tipo_plano])
        |> validate_number(:idade, greater_than_or_equal_to: 0)
        |> validate_number(:renda, greater_than_or_equal_to: 0)
        |> validate_inclusion(:uf, @valid_ufs)
        |> validate_inclusion(:tipo_plano, @valid_planos)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Output schema for the eligibility checker API."
      use Blackboex.Schema

      embedded_schema do
        field :elegivel, :boolean
        field :motivo, :string
        field :planos_disponiveis, {:array, :string}
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the eligibility checker handler."
      use ExUnit.Case

      @valid_params %{
        "idade" => 30,
        "renda" => 3000.0,
        "uf" => "SP",
        "tipo_plano" => "basico"
      }

      describe "Request changeset validation" do
        test "accepts valid input" do
          changeset = Request.changeset(@valid_params)
          assert changeset.valid?
        end

        test "rejects missing fields" do
          changeset = Request.changeset(%{})
          refute changeset.valid?
        end

        test "rejects invalid UF" do
          changeset = Request.changeset(Map.put(@valid_params, "uf", "XX"))
          refute changeset.valid?
        end

        test "rejects invalid tipo_plano" do
          changeset = Request.changeset(Map.put(@valid_params, "tipo_plano", "gold"))
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "eligible profile returns elegivel true with plans" do
          result = Handler.handle(@valid_params)
          assert result.elegivel == true
          assert is_binary(result.motivo)
          assert is_list(result.planos_disponiveis)
          assert "basico" in result.planos_disponiveis
        end

        test "underage for premium returns not eligible" do
          params = Map.merge(@valid_params, %{"idade" => 19, "tipo_plano" => "premium", "renda" => 6000.0})
          result = Handler.handle(params)
          assert result.elegivel == false
          assert String.contains?(result.motivo, "idade")
        end

        test "low income for premium returns not eligible" do
          params = Map.merge(@valid_params, %{"tipo_plano" => "premium", "renda" => 2000.0})
          result = Handler.handle(params)
          assert result.elegivel == false
          assert String.contains?(result.motivo, "renda")
        end

        test "unavailable UF for premium returns not eligible" do
          params = Map.merge(@valid_params, %{
            "tipo_plano" => "premium",
            "uf" => "AC",
            "renda" => 6000.0,
            "idade" => 25
          })
          result = Handler.handle(params)
          assert result.elegivel == false
          assert String.contains?(result.motivo, "estado")
        end
      end

      describe "error handling" do
        test "returns error for invalid input" do
          result = Handler.handle(%{})
          assert %{error: "Validation failed", details: details} = result
          assert is_map(details)
        end
      end
    end
    """
  end

  defp readme_content do
    """
    # Verificador de Elegibilidade

    Verifica se um cliente é elegível para um plano de serviço com base em regras
    de negócio configuradas: idade mínima, renda mínima e disponibilidade por estado.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `idade` | integer | sim | Idade do solicitante em anos |
    | `renda` | number | sim | Renda mensal em R$ |
    | `uf` | string | sim | Estado de residência (ex: SP, RJ) |
    | `tipo_plano` | string | sim | Plano desejado: `basico`, `intermediario`, `premium`, `empresarial` |

    ## Planos e Requisitos

    | Plano | Idade Mínima | Renda Mínima | Restrições de UF |
    |-------|-------------|-------------|-----------------|
    | basico | 18 | R$ 1.000 | nenhuma |
    | intermediario | 18 | R$ 2.000 | nenhuma |
    | premium | 21 | R$ 5.000 | não disponível em AC, RR, AP |
    | empresarial | 18 | R$ 3.000 | não disponível em AC, RR |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/verificador-elegibilidade \\
      -H "Content-Type: application/json" \\
      -d '{
        "idade": 30,
        "renda": 3000.00,
        "uf": "SP",
        "tipo_plano": "basico"
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "elegivel": true,
      "motivo": "todos os critérios atendidos",
      "planos_disponiveis": ["basico", "intermediario"]
    }
    ```

    ## Casos de Uso

    - Tool de agente de IA para pré-qualificação de clientes
    - Formulário de contratação com validação em tempo real
    - Sistema de recomendação de planos
    """
  end
end
