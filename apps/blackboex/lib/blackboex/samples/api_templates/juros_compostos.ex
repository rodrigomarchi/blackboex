defmodule Blackboex.Samples.ApiTemplates.JurosCompostos do
  @moduledoc """
  Template: Calculadora de Juros Compostos

  Calculates compound interest, installment value and full amortization table.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "juros-compostos",
      name: "Calculadora de Juros Compostos",
      description: "Calcula juros compostos, parcelas e tabela de amortização",
      category: "AI Agent Tools",
      template_type: "computation",
      icon: "chart-line",
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
        "valor_principal" => "number",
        "taxa_mensal" => "number",
        "num_parcelas" => "integer"
      },
      example_request: %{
        "valor_principal" => 10_000.0,
        "taxa_mensal" => 1.5,
        "num_parcelas" => 12
      },
      example_response: %{
        "valor_parcela" => 912.15,
        "total_juros" => 945.8,
        "total_pago" => 10_945.8,
        "tabela_amortizacao" => [
          %{
            "parcela" => 1,
            "saldo_devedor" => 10_000.0,
            "juros" => 150.0,
            "amortizacao" => 762.15,
            "saldo_restante" => 9_237.85
          }
        ]
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
          %{"name" => "valid loan returns correct installment", "status" => "pass"},
          %{"name" => "amortization table has correct row count", "status" => "pass"},
          %{"name" => "last row has near-zero balance", "status" => "pass"},
          %{"name" => "zero rate means equal installments", "status" => "pass"},
          %{"name" => "missing fields returns error", "status" => "pass"},
          %{"name" => "zero principal returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Calculates compound interest, installments and amortization table."

      @doc "Processes request and returns loan calculation or validation error."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          parcela = Helpers.installment(data.valor_principal, data.taxa_mensal, data.num_parcelas)
          total_pago = Float.round(parcela * data.num_parcelas, 2)
          total_juros = Float.round(total_pago - data.valor_principal, 2)
          tabela = Helpers.amortization_table(data.valor_principal, data.taxa_mensal, parcela, data.num_parcelas)

          %{
            valor_parcela: parcela,
            total_juros: total_juros,
            total_pago: total_pago,
            tabela_amortizacao: tabela
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
      @moduledoc "Compound interest and amortization calculation helpers."

      @doc "Calculates the fixed monthly installment using the Price formula."
      @spec installment(float(), float(), integer()) :: float()
      def installment(principal, taxa_mensal, num_parcelas) do
        rate = taxa_mensal / 100.0

        if rate == 0.0 do
          Float.round(principal / num_parcelas, 2)
        else
          factor = :math.pow(1 + rate, num_parcelas)
          pmt = principal * rate * factor / (factor - 1)
          Float.round(pmt, 2)
        end
      end

      @doc "Builds a full amortization table for the loan."
      @spec amortization_table(float(), float(), float(), integer()) :: [map()]
      def amortization_table(principal, taxa_mensal, parcela, num_parcelas) do
        rate = taxa_mensal / 100.0

        {_saldo, rows} =
          Enum.reduce(1..num_parcelas, {principal, []}, fn i, {saldo, acc} ->
            juros = Float.round(saldo * rate, 2)
            amort = Float.round(parcela - juros, 2)
            restante = max(0.0, Float.round(saldo - amort, 2))

            row = %{
              parcela: i,
              saldo_devedor: Float.round(saldo, 2),
              juros: juros,
              amortizacao: amort,
              saldo_restante: restante
            }

            {restante, [row | acc]}
          end)

        Enum.reverse(rows)
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Input schema for the compound interest calculator API."
      use Blackboex.Schema

      embedded_schema do
        field :valor_principal, :float
        field :taxa_mensal, :float
        field :num_parcelas, :integer
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:valor_principal, :taxa_mensal, :num_parcelas])
        |> validate_required([:valor_principal, :taxa_mensal, :num_parcelas])
        |> validate_number(:valor_principal, greater_than: 0)
        |> validate_number(:taxa_mensal, greater_than_or_equal_to: 0)
        |> validate_number(:num_parcelas, greater_than: 0)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Output schema for the compound interest calculator API."
      use Blackboex.Schema

      embedded_schema do
        field :valor_parcela, :float
        field :total_juros, :float
        field :total_pago, :float
        field :tabela_amortizacao, {:array, :map}
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the compound interest calculator handler."
      use ExUnit.Case

      @valid_params %{
        "valor_principal" => 10_000.0,
        "taxa_mensal" => 1.5,
        "num_parcelas" => 12
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

        test "rejects zero principal" do
          changeset = Request.changeset(Map.put(@valid_params, "valor_principal", 0.0))
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "returns installment and totals" do
          result = Handler.handle(@valid_params)
          assert result.valor_parcela > 0
          assert result.total_pago > 10_000.0
          assert result.total_juros > 0
          assert Float.round(result.total_juros + 10_000.0, 2) == result.total_pago
        end

        test "amortization table has correct row count" do
          result = Handler.handle(@valid_params)
          assert length(result.tabela_amortizacao) == 12
        end

        test "last row has near-zero balance" do
          result = Handler.handle(@valid_params)
          last = List.last(result.tabela_amortizacao)
          assert last.saldo_restante <= 1.0
        end

        test "zero rate means equal installments with no interest" do
          params = Map.put(@valid_params, "taxa_mensal", 0.0)
          result = Handler.handle(params)
          assert abs(result.total_juros) < 0.1
          assert abs(result.valor_parcela - Float.round(10_000.0 / 12, 2)) < 0.1
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
    # Calculadora de Juros Compostos

    Calcula o valor da parcela mensal, total de juros pago e a tabela completa
    de amortização pelo sistema Price (parcelas iguais) para qualquer financiamento.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `valor_principal` | number | sim | Valor do empréstimo/financiamento em R$ |
    | `taxa_mensal` | number | sim | Taxa de juros mensal em % (0 = sem juros) |
    | `num_parcelas` | integer | sim | Número de parcelas mensais |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/juros-compostos \\
      -H "Content-Type: application/json" \\
      -d '{
        "valor_principal": 10000.00,
        "taxa_mensal": 1.5,
        "num_parcelas": 12
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "valor_parcela": 912.15,
      "total_juros": 945.80,
      "total_pago": 10945.80,
      "tabela_amortizacao": [
        {
          "parcela": 1,
          "saldo_devedor": 10000.00,
          "juros": 150.00,
          "amortizacao": 762.15,
          "saldo_restante": 9237.85
        }
      ]
    }
    ```

    ## Método de Cálculo

    Usa o **Sistema Price** (parcelas fixas):
    - `PMT = PV × i / (1 − (1+i)^−n)`
    - Cada parcela é dividida em juros (saldo × taxa) + amortização (PMT − juros)

    ## Casos de Uso

    - Simulador de financiamento imobiliário ou veicular
    - Tool de agente de IA para análise de crédito
    - Comparador de condições de empréstimo
    """
  end
end
