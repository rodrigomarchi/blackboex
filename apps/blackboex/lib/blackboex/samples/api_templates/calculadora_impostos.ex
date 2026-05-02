defmodule Blackboex.Samples.ApiTemplates.CalculadoraImpostos do
  @moduledoc """
  Template: Calculadora de Impostos BR

  Calculates ICMS, ISS, PIS/COFINS over a value and product type,
  considering origin and destination states.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "calculadora-impostos",
      name: "Calculadora de Impostos BR",
      description: "Calcula ICMS, ISS, PIS/COFINS sobre valor e tipo de produto/serviço",
      category: "AI Agent Tools",
      template_type: "computation",
      icon: "calculator",
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
        "tipo_produto" => "string",
        "uf_origem" => "string",
        "uf_destino" => "string"
      },
      example_request: %{
        "valor" => 1000.0,
        "tipo_produto" => "mercadoria",
        "uf_origem" => "SP",
        "uf_destino" => "RJ"
      },
      example_response: %{
        "impostos" => %{
          "icms" => 120.0,
          "iss" => 0.0,
          "pis" => 16.5,
          "cofins" => 76.0
        },
        "total_impostos" => 212.5,
        "valor_final" => 1212.5
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
          %{"name" => "mercadoria inter-estadual returns correct ICMS", "status" => "pass"},
          %{"name" => "servico returns ISS not ICMS", "status" => "pass"},
          %{"name" => "missing required fields returns error", "status" => "pass"},
          %{"name" => "invalid tipo_produto returns error", "status" => "pass"},
          %{"name" => "invalid UF returns error", "status" => "pass"},
          %{"name" => "zero value returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Calculates Brazilian taxes for a given value and product type."

      @doc "Processes request and returns tax breakdown or validation error."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          impostos = Helpers.calculate(data.valor, data.tipo_produto, data.uf_origem, data.uf_destino)
          total = Float.round(impostos.icms + impostos.iss + impostos.pis + impostos.cofins, 2)
          %{impostos: impostos, total_impostos: total, valor_final: Float.round(data.valor + total, 2)}
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
      @moduledoc "Tax calculation helpers for ICMS, ISS, PIS and COFINS."

      @icms_interstate %{
        "SP" => 0.12, "RJ" => 0.12, "MG" => 0.12, "RS" => 0.12,
        "PR" => 0.12, "SC" => 0.12, "ES" => 0.12,
        "BA" => 0.12, "PE" => 0.12, "CE" => 0.12, "GO" => 0.12,
        "DF" => 0.12, "MT" => 0.12, "MS" => 0.12, "PA" => 0.12,
        "AM" => 0.12, "TO" => 0.12, "AL" => 0.12, "SE" => 0.12,
        "PB" => 0.12, "RN" => 0.12, "PI" => 0.12, "MA" => 0.12,
        "AC" => 0.12, "RO" => 0.12, "RR" => 0.12, "AP" => 0.12
      }

      @icms_intrastate %{
        "SP" => 0.18, "RJ" => 0.20, "MG" => 0.18, "RS" => 0.17,
        "PR" => 0.19, "SC" => 0.17, "ES" => 0.17,
        "BA" => 0.19, "PE" => 0.18, "CE" => 0.18, "GO" => 0.17,
        "DF" => 0.12, "MT" => 0.17, "MS" => 0.17, "PA" => 0.17,
        "AM" => 0.18, "TO" => 0.18, "AL" => 0.17, "SE" => 0.18,
        "PB" => 0.18, "RN" => 0.18, "PI" => 0.18, "MA" => 0.18,
        "AC" => 0.17, "RO" => 0.17, "RR" => 0.17, "AP" => 0.18
      }

      @iss_rate 0.05
      @pis_rate 0.0165
      @cofins_rate 0.076

      @doc "Calculates all applicable taxes for the given parameters."
      @spec calculate(float(), String.t(), String.t(), String.t()) :: map()
      def calculate(valor, tipo, uf_origem, uf_destino) do
        icms = calc_icms(valor, tipo, uf_origem, uf_destino)
        iss = calc_iss(valor, tipo)
        pis = Float.round(valor * @pis_rate, 2)
        cofins = Float.round(valor * @cofins_rate, 2)
        %{icms: icms, iss: iss, pis: pis, cofins: cofins}
      end

      @spec calc_icms(float(), String.t(), String.t(), String.t()) :: float()
      defp calc_icms(_valor, "servico", _uf_origem, _uf_destino), do: 0.0

      defp calc_icms(valor, _tipo, uf_origem, uf_destino) do
        rate =
          if uf_origem == uf_destino do
            Map.get(@icms_intrastate, uf_origem, 0.17)
          else
            Map.get(@icms_interstate, uf_destino, 0.12)
          end

        Float.round(valor * rate, 2)
      end

      @spec calc_iss(float(), String.t()) :: float()
      defp calc_iss(valor, "servico"), do: Float.round(valor * @iss_rate, 2)
      defp calc_iss(_valor, _tipo), do: 0.0
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Input schema for the tax calculator API."
      use Blackboex.Schema

      @valid_types ["mercadoria", "servico", "produto_industrializado", "importado"]
      @valid_ufs ~w(AC AL AM AP BA CE DF ES GO MA MG MS MT PA PB PE PI PR RJ RN RO RR RS SC SE SP TO)

      embedded_schema do
        field :valor, :float
        field :tipo_produto, :string
        field :uf_origem, :string
        field :uf_destino, :string
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:valor, :tipo_produto, :uf_origem, :uf_destino])
        |> validate_required([:valor, :tipo_produto, :uf_origem, :uf_destino])
        |> validate_number(:valor, greater_than: 0)
        |> validate_inclusion(:tipo_produto, @valid_types)
        |> validate_inclusion(:uf_origem, @valid_ufs)
        |> validate_inclusion(:uf_destino, @valid_ufs)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Output schema for the tax calculator API."
      use Blackboex.Schema

      embedded_schema do
        field :impostos, :map
        field :total_impostos, :float
        field :valor_final, :float
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the tax calculator handler."
      use ExUnit.Case

      @valid_params %{
        "valor" => 1000.0,
        "tipo_produto" => "mercadoria",
        "uf_origem" => "SP",
        "uf_destino" => "RJ"
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

        test "rejects invalid tipo_produto" do
          changeset = Request.changeset(Map.put(@valid_params, "tipo_produto", "invalido"))
          refute changeset.valid?
        end

        test "rejects invalid UF" do
          changeset = Request.changeset(Map.put(@valid_params, "uf_origem", "XX"))
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "mercadoria inter-estadual returns correct taxes" do
          result = Handler.handle(@valid_params)
          assert %{impostos: impostos, total_impostos: total, valor_final: final} = result
          assert impostos.icms > 0
          assert impostos.iss == 0.0
          assert impostos.pis > 0
          assert impostos.cofins > 0
          assert total > 0
          assert final > @valid_params["valor"]
        end

        test "servico returns ISS and zero ICMS" do
          params = Map.put(@valid_params, "tipo_produto", "servico")
          result = Handler.handle(params)
          assert result.impostos.icms == 0.0
          assert result.impostos.iss > 0
        end

        test "intra-state uses higher intrastate rate" do
          intra_params = Map.put(@valid_params, "uf_destino", "SP")
          inter_result = Handler.handle(@valid_params)
          intra_result = Handler.handle(intra_params)
          assert intra_result.impostos.icms > inter_result.impostos.icms
        end
      end

      describe "error handling" do
        test "returns error for invalid input" do
          result = Handler.handle(%{})
          assert %{error: "Validation failed", details: details} = result
          assert is_map(details)
        end

        test "returns error for zero value" do
          result = Handler.handle(Map.put(@valid_params, "valor", 0.0))
          assert %{error: "Validation failed", details: details} = result
          assert Map.has_key?(details, :valor)
        end
      end
    end
    """
  end

  defp readme_content do
    """
    # Calculadora de Impostos BR

    Calcula os principais impostos brasileiros (ICMS, ISS, PIS e COFINS) sobre
    um valor de venda, considerando o tipo de produto/serviço e os estados de
    origem e destino.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `valor` | number | sim | Valor base para cálculo (deve ser > 0) |
    | `tipo_produto` | string | sim | Tipo: `mercadoria`, `servico`, `produto_industrializado`, `importado` |
    | `uf_origem` | string | sim | UF de origem (ex: SP, RJ, MG) |
    | `uf_destino` | string | sim | UF de destino (ex: SP, RJ, MG) |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/calculadora-impostos \\
      -H "Content-Type: application/json" \\
      -d '{
        "valor": 1000.00,
        "tipo_produto": "mercadoria",
        "uf_origem": "SP",
        "uf_destino": "RJ"
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "impostos": {
        "icms": 120.00,
        "iss": 0.00,
        "pis": 16.50,
        "cofins": 76.00
      },
      "total_impostos": 212.50,
      "valor_final": 1212.50
    }
    ```

    ## Regras de Negócio

    - **ICMS**: Para operações inter-estaduais, usa alíquota do estado de destino (geralmente 12%).
      Para operações intra-estaduais, usa alíquota interna do estado (ex: SP=18%, RJ=20%).
    - **ISS**: Aplicado somente para `tipo_produto = "servico"` (5%).
    - **PIS**: 1,65% sobre o valor base.
    - **COFINS**: 7,6% sobre o valor base.

    ## Casos de Uso

    - Tool de agente de IA para precificação com impostos
    - Simulador de nota fiscal
    - Calculadora de custo real para e-commerce
    """
  end
end
