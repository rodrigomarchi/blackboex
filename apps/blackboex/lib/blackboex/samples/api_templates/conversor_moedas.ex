defmodule Blackboex.Samples.ApiTemplates.ConversorMoedas do
  @moduledoc """
  Template: Conversor de Moedas

  Converts between currencies using hardcoded reference rates.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "conversor-moedas",
      name: "Conversor de Moedas",
      description: "Converte entre moedas com taxas de referência hardcoded",
      category: "AI Agent Tools",
      template_type: "computation",
      icon: "currency-dollar",
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
        "valor" => "number",
        "moeda_origem" => "string",
        "moeda_destino" => "string"
      },
      example_request: %{
        "valor" => 100.0,
        "moeda_origem" => "USD",
        "moeda_destino" => "BRL"
      },
      example_response: %{
        "valor_convertido" => 497.01,
        "taxa" => 4.970_149,
        "data_referencia" => "2024-01-15"
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
          %{"name" => "USD to BRL returns converted value", "status" => "pass"},
          %{"name" => "same currency returns same value with rate 1", "status" => "pass"},
          %{"name" => "reverse conversion is consistent", "status" => "pass"},
          %{"name" => "unknown currency returns error", "status" => "pass"},
          %{"name" => "zero value returns error", "status" => "pass"},
          %{"name" => "missing fields returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Converts currency values using hardcoded reference rates."

      @doc "Processes request and returns converted value or validation error."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)

          case Helpers.convert(data.valor, data.moeda_origem, data.moeda_destino) do
            {:ok, resultado} ->
              resultado

            {:error, reason} ->
              %{error: "Validation failed", details: %{moeda: [reason]}}
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
      @moduledoc "Currency conversion helpers with hardcoded BRL-based rates."

      @rates_from_brl %{
        "BRL" => 1.0,
        "USD" => 0.2012,
        "EUR" => 0.1854,
        "GBP" => 0.1587,
        "ARS" => 175.32,
        "CLP" => 188.45,
        "COP" => 789.50,
        "MXN" => 3.41,
        "PYG" => 1_482.0,
        "UYU" => 7.85,
        "CAD" => 0.2731,
        "AUD" => 0.3052,
        "JPY" => 30.12,
        "CNY" => 1.458,
        "CHF" => 0.1789
      }

      @reference_date "2024-01-15"

      @doc "Converts a value from one currency to another via BRL pivot."
      @spec convert(float(), String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
      def convert(valor, moeda_origem, moeda_destino) do
        with {:ok, rate_origem} <- get_rate(moeda_origem),
             {:ok, rate_destino} <- get_rate(moeda_destino) do
          in_brl = valor / rate_origem
          converted = in_brl * rate_destino
          taxa = Float.round(rate_destino / rate_origem, 6)

          {:ok,
           %{
             valor_convertido: Float.round(converted, 2),
             taxa: taxa,
             data_referencia: @reference_date
           }}
        end
      end

      @doc "Returns supported currency codes."
      @spec supported_currencies() :: [String.t()]
      def supported_currencies, do: Map.keys(@rates_from_brl)

      @spec get_rate(String.t()) :: {:ok, float()} | {:error, String.t()}
      defp get_rate(moeda) do
        case Map.get(@rates_from_brl, moeda) do
          nil -> {:error, "unsupported currency: #{moeda}"}
          rate -> {:ok, rate}
        end
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Input schema for the currency converter API."
      use Blackboex.Schema

      @supported ~w(BRL USD EUR GBP ARS CLP COP MXN PYG UYU CAD AUD JPY CNY CHF)

      embedded_schema do
        field :valor, :float
        field :moeda_origem, :string
        field :moeda_destino, :string
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:valor, :moeda_origem, :moeda_destino])
        |> validate_required([:valor, :moeda_origem, :moeda_destino])
        |> validate_number(:valor, greater_than: 0)
        |> validate_inclusion(:moeda_origem, @supported)
        |> validate_inclusion(:moeda_destino, @supported)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Output schema for the currency converter API."
      use Blackboex.Schema

      embedded_schema do
        field :valor_convertido, :float
        field :taxa, :float
        field :data_referencia, :string
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the currency converter handler."
      use ExUnit.Case

      describe "Request changeset validation" do
        test "accepts valid input" do
          changeset = Request.changeset(%{
            "valor" => 100.0,
            "moeda_origem" => "USD",
            "moeda_destino" => "BRL"
          })
          assert changeset.valid?
        end

        test "rejects missing fields" do
          changeset = Request.changeset(%{})
          refute changeset.valid?
        end

        test "rejects unknown currency" do
          changeset = Request.changeset(%{
            "valor" => 100.0,
            "moeda_origem" => "XYZ",
            "moeda_destino" => "BRL"
          })
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "USD to BRL returns value greater than original" do
          result = Handler.handle(%{"valor" => 100.0, "moeda_origem" => "USD", "moeda_destino" => "BRL"})
          assert result.valor_convertido > 100.0
          assert result.taxa > 1.0
          assert is_binary(result.data_referencia)
        end

        test "BRL to USD returns fraction" do
          result = Handler.handle(%{"valor" => 500.0, "moeda_origem" => "BRL", "moeda_destino" => "USD"})
          assert result.valor_convertido < 500.0
          assert result.taxa < 1.0
        end

        test "same currency returns same value with rate 1.0" do
          result = Handler.handle(%{"valor" => 100.0, "moeda_origem" => "BRL", "moeda_destino" => "BRL"})
          assert result.valor_convertido == 100.0
          assert result.taxa == 1.0
        end
      end

      describe "error handling" do
        test "returns error for invalid input" do
          result = Handler.handle(%{})
          assert %{error: "Validation failed", details: details} = result
          assert is_map(details)
        end

        test "returns error for zero value" do
          result = Handler.handle(%{"valor" => 0.0, "moeda_origem" => "USD", "moeda_destino" => "BRL"})
          assert %{error: "Validation failed", details: details} = result
          assert Map.has_key?(details, :valor)
        end
      end
    end
    """
  end

  defp readme_content do
    """
    # Conversor de Moedas

    Converte valores entre 15 moedas usando taxas de referência hardcoded.
    Ideal como tool de agente de IA para cálculos financeiros e comparações de preço.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `valor` | number | sim | Valor a converter (deve ser > 0) |
    | `moeda_origem` | string | sim | Código ISO da moeda de origem |
    | `moeda_destino` | string | sim | Código ISO da moeda de destino |

    ## Moedas Suportadas

    BRL, USD, EUR, GBP, ARS, CLP, COP, MXN, PYG, UYU, CAD, AUD, JPY, CNY, CHF

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/conversor-moedas \\
      -H "Content-Type: application/json" \\
      -d '{"valor": 100.0, "moeda_origem": "USD", "moeda_destino": "BRL"}'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "valor_convertido": 497.01,
      "taxa": 4.970149,
      "data_referencia": "2024-01-15"
    }
    ```

    ## Casos de Uso

    - Tool de agente de IA para comparação de preços internacionais
    - Calculadora de custo de importação
    - Dashboard financeiro com conversão de valores
    """
  end
end
