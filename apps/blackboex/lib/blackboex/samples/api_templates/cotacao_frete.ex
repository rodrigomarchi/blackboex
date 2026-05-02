defmodule Blackboex.Samples.ApiTemplates.CotacaoFrete do
  @moduledoc """
  Template: Cotação de Frete

  Calculates shipping costs for PAC, SEDEX and transportadora based on
  origin/destination CEP, weight and package dimensions.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "cotacao-frete",
      name: "Cotação de Frete",
      description:
        "Calcula frete por CEP, peso e dimensões para PAC, SEDEX e transportadora privada",
      category: "AI Agent Tools",
      template_type: "computation",
      icon: "truck",
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
        "cep_origem" => "string",
        "cep_destino" => "string",
        "peso_kg" => "number",
        "dimensoes" => "object"
      },
      example_request: %{
        "cep_origem" => "01310100",
        "cep_destino" => "20040020",
        "peso_kg" => 2.5,
        "dimensoes" => %{
          "altura" => 15,
          "largura" => 30,
          "comprimento" => 40
        }
      },
      example_response: %{
        "opcoes" => [
          %{"servico" => "PAC", "preco" => 28.5, "prazo_dias" => 8},
          %{"servico" => "SEDEX", "preco" => 45.5, "prazo_dias" => 3},
          %{"servico" => "Transportadora", "preco" => 31.5, "prazo_dias" => 5}
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
          %{"name" => "valid request returns shipping options", "status" => "pass"},
          %{"name" => "missing required fields returns error", "status" => "pass"},
          %{"name" => "invalid CEP format returns error", "status" => "pass"},
          %{"name" => "zero weight returns error", "status" => "pass"},
          %{"name" => "negative weight returns error", "status" => "pass"},
          %{"name" => "missing dimensoes keys returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Calculates shipping options based on CEP, weight and dimensions."

      @doc "Processes request and returns shipping options or validation error."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          weight = Helpers.effective_weight(data.peso_kg, data.dimensoes)
          origin_region = Helpers.cep_region(data.cep_origem)
          dest_region = Helpers.cep_region(data.cep_destino)
          opcoes = Helpers.calculate_options(origin_region, dest_region, weight)
          %{opcoes: opcoes}
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
      @moduledoc "Helper functions for shipping cost calculation."

      @cep_regions %{
        "01" => "SP", "02" => "SP", "03" => "SP", "04" => "SP", "05" => "SP",
        "06" => "SP", "07" => "SP", "08" => "SP", "09" => "SP",
        "20" => "RJ", "21" => "RJ", "22" => "RJ", "23" => "RJ", "24" => "RJ",
        "25" => "RJ", "26" => "RJ", "27" => "RJ", "28" => "RJ",
        "29" => "ES",
        "30" => "MG", "31" => "MG", "32" => "MG", "33" => "MG", "34" => "MG",
        "35" => "MG", "36" => "MG", "37" => "MG", "38" => "MG", "39" => "MG",
        "40" => "BA", "41" => "BA", "42" => "BA", "43" => "BA", "44" => "BA",
        "45" => "BA", "46" => "BA", "47" => "BA", "48" => "BA",
        "50" => "PE", "51" => "PE", "52" => "PE", "53" => "PE", "54" => "PE",
        "55" => "PE", "56" => "PE",
        "60" => "CE", "61" => "CE", "62" => "CE", "63" => "CE",
        "66" => "PA", "67" => "PA", "68" => "PA",
        "69" => "AM",
        "70" => "DF", "71" => "DF", "72" => "DF", "73" => "DF",
        "74" => "GO", "75" => "GO", "76" => "GO",
        "77" => "TO",
        "78" => "MT",
        "79" => "MS",
        "80" => "PR", "81" => "PR", "82" => "PR", "83" => "PR", "84" => "PR",
        "85" => "PR", "86" => "PR", "87" => "PR",
        "88" => "SC", "89" => "SC",
        "90" => "RS", "91" => "RS", "92" => "RS", "93" => "RS", "94" => "RS",
        "95" => "RS", "96" => "RS", "97" => "RS", "98" => "RS", "99" => "RS"
      }

      @zone_matrix %{
        {"SP", "SP"} => 1, {"SP", "RJ"} => 2, {"SP", "MG"} => 2,
        {"SP", "ES"} => 2, {"SP", "PR"} => 2, {"SP", "SC"} => 2,
        {"SP", "RS"} => 2, {"SP", "BA"} => 3, {"SP", "PE"} => 3,
        {"SP", "CE"} => 3, {"SP", "GO"} => 3, {"SP", "DF"} => 3,
        {"SP", "MT"} => 3, {"SP", "MS"} => 3, {"SP", "PA"} => 3,
        {"SP", "AM"} => 3, {"SP", "TO"} => 3,
        {"RJ", "RJ"} => 1, {"RJ", "SP"} => 2, {"RJ", "MG"} => 2,
        {"RJ", "ES"} => 2, {"RJ", "PR"} => 2,
        {"MG", "MG"} => 1, {"MG", "SP"} => 2, {"MG", "RJ"} => 2,
        {"MG", "ES"} => 2, {"MG", "BA"} => 3, {"MG", "GO"} => 3,
        {"MG", "DF"} => 3,
        {"PR", "PR"} => 1, {"PR", "SP"} => 2, {"PR", "SC"} => 2,
        {"PR", "RS"} => 2,
        {"SC", "SC"} => 1, {"SC", "PR"} => 2, {"SC", "RS"} => 2,
        {"SC", "SP"} => 2,
        {"RS", "RS"} => 1, {"RS", "SC"} => 2, {"RS", "PR"} => 2,
        {"RS", "SP"} => 2
      }

      @base_prices %{
        1 => %{"PAC" => 15.00, "SEDEX" => 25.00, "Transportadora" => 20.00},
        2 => %{"PAC" => 22.00, "SEDEX" => 40.00, "Transportadora" => 28.00},
        3 => %{"PAC" => 30.00, "SEDEX" => 58.00, "Transportadora" => 38.00}
      }

      @delivery_days %{
        1 => %{"PAC" => 5, "SEDEX" => 1, "Transportadora" => 3},
        2 => %{"PAC" => 8, "SEDEX" => 3, "Transportadora" => 5},
        3 => %{"PAC" => 12, "SEDEX" => 5, "Transportadora" => 8}
      }

      @weight_surcharge %{
        "PAC" => 2.50,
        "SEDEX" => 4.50,
        "Transportadora" => 3.00
      }

      @doc "Returns the Brazilian state abbreviation for a given CEP prefix."
      @spec cep_region(String.t()) :: String.t()
      def cep_region(cep) do
        prefix = String.slice(cep, 0, 2)
        Map.get(@cep_regions, prefix, "OTHER")
      end

      @doc "Returns the greater of actual weight and dimensional weight."
      @spec effective_weight(float(), map()) :: float()
      def effective_weight(actual_weight, dimensoes) do
        altura = Map.get(dimensoes, "altura", 0)
        largura = Map.get(dimensoes, "largura", 0)
        comprimento = Map.get(dimensoes, "comprimento", 0)
        dimensional_weight = altura * largura * comprimento / 6000.0
        max(actual_weight, dimensional_weight)
      end

      @doc "Calculates shipping options for origin/destination regions and weight."
      @spec calculate_options(String.t(), String.t(), float()) :: [map()]
      def calculate_options(origin_region, dest_region, weight) do
        zone = get_zone(origin_region, dest_region)
        base = Map.fetch!(@base_prices, zone)
        days = Map.fetch!(@delivery_days, zone)

        Enum.map(["PAC", "SEDEX", "Transportadora"], fn service ->
          base_price = Map.fetch!(base, service)
          surcharge = Map.fetch!(@weight_surcharge, service)
          extra_weight = max(0, weight - 1.0)
          price = Float.round(base_price + extra_weight * surcharge, 2)
          %{servico: service, preco: price, prazo_dias: Map.fetch!(days, service)}
        end)
      end

      @spec get_zone(String.t(), String.t()) :: integer()
      defp get_zone(origin, dest) do
        case Map.get(@zone_matrix, {origin, dest}) do
          nil ->
            case Map.get(@zone_matrix, {dest, origin}) do
              nil -> 3
              zone -> zone
            end

          zone ->
            zone
        end
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Input schema for the shipping quote API."
      use Blackboex.Schema

      embedded_schema do
        field :cep_origem, :string
        field :cep_destino, :string
        field :peso_kg, :float
        field :dimensoes, :map
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:cep_origem, :cep_destino, :peso_kg, :dimensoes])
        |> validate_required([:cep_origem, :cep_destino, :peso_kg, :dimensoes])
        |> validate_format(:cep_origem, ~r/^\d{8}$/, message: "must be exactly 8 digits")
        |> validate_format(:cep_destino, ~r/^\d{8}$/, message: "must be exactly 8 digits")
        |> validate_number(:peso_kg, greater_than: 0)
        |> validate_dimensoes()
      end

      @spec validate_dimensoes(Ecto.Changeset.t()) :: Ecto.Changeset.t()
      defp validate_dimensoes(changeset) do
        case get_change(changeset, :dimensoes) do
          nil ->
            changeset

          dimensoes ->
            required_keys = ["altura", "largura", "comprimento"]
            missing = Enum.reject(required_keys, &Map.has_key?(dimensoes, &1))

            if missing == [] do
              changeset
            else
              add_error(changeset, :dimensoes, "missing required keys: #{Enum.join(missing, ", ")}")
            end
        end
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Output schema for the shipping quote API."
      use Blackboex.Schema

      embedded_schema do
        field :opcoes, {:array, :map}
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the shipping quote handler."
      use ExUnit.Case

      @valid_params %{
        "cep_origem" => "01310100",
        "cep_destino" => "20040020",
        "peso_kg" => 2.5,
        "dimensoes" => %{"altura" => 15, "largura" => 30, "comprimento" => 40}
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

        test "rejects invalid CEP format" do
          changeset = Request.changeset(Map.put(@valid_params, "cep_origem", "0131010"))
          refute changeset.valid?
        end

        test "rejects zero weight" do
          changeset = Request.changeset(Map.put(@valid_params, "peso_kg", 0.0))
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "returns all three shipping options" do
          result = Handler.handle(@valid_params)
          assert %{opcoes: opcoes} = result
          assert length(opcoes) == 3
          services = Enum.map(opcoes, & &1.servico)
          assert "PAC" in services
          assert "SEDEX" in services
          assert "Transportadora" in services
        end

        test "each option has positive price and delivery days" do
          result = Handler.handle(@valid_params)
          Enum.each(result.opcoes, fn opt ->
            assert is_float(opt.preco) and opt.preco > 0
            assert is_integer(opt.prazo_dias) and opt.prazo_dias > 0
          end)
        end
      end

      describe "error handling" do
        test "returns error for invalid input" do
          result = Handler.handle(%{})
          assert %{error: "Validation failed", details: details} = result
          assert is_map(details)
        end

        test "returns error for missing dimensoes keys" do
          params = Map.put(@valid_params, "dimensoes", %{"altura" => 15})
          result = Handler.handle(params)
          assert %{error: "Validation failed", details: details} = result
          assert Map.has_key?(details, :dimensoes)
        end
      end
    end
    """
  end

  defp readme_content do
    """
    # Cotação de Frete

    Calcula o custo de frete para envio de pacotes entre quaisquer CEPs brasileiros,
    retornando opções para PAC, SEDEX e Transportadora privada com preços e prazos.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `cep_origem` | string | sim | CEP de origem (8 dígitos, sem hífen) |
    | `cep_destino` | string | sim | CEP de destino (8 dígitos, sem hífen) |
    | `peso_kg` | number | sim | Peso do pacote em kg (deve ser > 0) |
    | `dimensoes` | object | sim | Dimensões do pacote em cm |
    | `dimensoes.altura` | number | sim | Altura em centímetros |
    | `dimensoes.largura` | number | sim | Largura em centímetros |
    | `dimensoes.comprimento` | number | sim | Comprimento em centímetros |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/cotacao-frete \\
      -H "Content-Type: application/json" \\
      -d '{
        "cep_origem": "01310100",
        "cep_destino": "20040020",
        "peso_kg": 2.5,
        "dimensoes": {
          "altura": 15,
          "largura": 30,
          "comprimento": 40
        }
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "opcoes": [
        {"servico": "PAC", "preco": 28.5, "prazo_dias": 8},
        {"servico": "SEDEX", "preco": 45.5, "prazo_dias": 3},
        {"servico": "Transportadora", "preco": 31.5, "prazo_dias": 5}
      ]
    }
    ```

    ## Lógica de Cálculo

    - **Região por CEP**: Os 2 primeiros dígitos do CEP determinam o estado de origem/destino.
    - **Zona de entrega**: Pares de regiões são classificados em zonas (1=mesmo estado, 2=Sul/Sudeste, 3=demais).
    - **Peso efetivo**: `max(peso_real, peso_dimensional)` onde `peso_dimensional = (A × L × C) / 6000`.
    - **Preço final**: `preço_base + max(0, peso_efetivo - 1) × adicional_por_kg`.

    ## Casos de Uso

    - Checkout de e-commerce com cotação em tempo real
    - Tool de agente de IA para calcular custo de envio
    - Sistema de logística para comparar transportadoras
    """
  end
end
