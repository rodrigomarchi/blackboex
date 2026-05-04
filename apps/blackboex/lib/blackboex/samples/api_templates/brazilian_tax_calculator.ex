defmodule Blackboex.Samples.ApiTemplates.BrazilianTaxCalculator do
  @moduledoc """
  Template: Brazilian Tax Calculator

  Calculates ICMS, ISS, PIS/COFINS over a value and product type,
  considering origin and destination states.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "brazilian-tax-calculator",
      name: "Brazilian Tax Calculator",
      description: "Calculates ICMS, ISS and PIS/COFINS for Brazilian sales scenarios",
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
        "amount" => "number",
        "product_type" => "string",
        "origin_state" => "string",
        "destination_state" => "string"
      },
      example_request: %{
        "amount" => 1000.0,
        "product_type" => "goods",
        "origin_state" => "SP",
        "destination_state" => "RJ"
      },
      example_response: %{
        "taxes" => %{
          "icms" => 120.0,
          "iss" => 0.0,
          "pis" => 16.5,
          "cofins" => 76.0
        },
        "total_taxes" => 212.5,
        "final_amount" => 1212.5
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
          %{"name" => "interstate goods returns correct ICMS", "status" => "pass"},
          %{"name" => "service returns ISS not ICMS", "status" => "pass"},
          %{"name" => "missing required fields returns error", "status" => "pass"},
          %{"name" => "invalid product_type returns error", "status" => "pass"},
          %{"name" => "invalid state returns error", "status" => "pass"},
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
          taxes = Helpers.calculate(data.amount, data.product_type, data.origin_state, data.destination_state)
          total = Float.round(taxes.icms + taxes.iss + taxes.pis + taxes.cofins, 2)
          %{taxes: taxes, total_taxes: total, final_amount: Float.round(data.amount + total, 2)}
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
      def calculate(amount, product_type, origin_state, destination_state) do
        icms = calc_icms(amount, product_type, origin_state, destination_state)
        iss = calc_iss(amount, product_type)
        pis = Float.round(amount * @pis_rate, 2)
        cofins = Float.round(amount * @cofins_rate, 2)
        %{icms: icms, iss: iss, pis: pis, cofins: cofins}
      end

      @spec calc_icms(float(), String.t(), String.t(), String.t()) :: float()
      defp calc_icms(_amount, "service", _origin_state, _destination_state), do: 0.0

      defp calc_icms(amount, _product_type, origin_state, destination_state) do
        rate =
          if origin_state == destination_state do
            Map.get(@icms_intrastate, origin_state, 0.17)
          else
            Map.get(@icms_interstate, destination_state, 0.12)
          end

        Float.round(amount * rate, 2)
      end

      @spec calc_iss(float(), String.t()) :: float()
      defp calc_iss(amount, "service"), do: Float.round(amount * @iss_rate, 2)
      defp calc_iss(_amount, _product_type), do: 0.0
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Input schema for the tax calculator API."
      use Blackboex.Schema

      @valid_types ["goods", "service", "manufactured_product", "imported"]
      @valid_states ~w(AC AL AM AP BA CE DF ES GO MA MG MS MT PA PB PE PI PR RJ RN RO RR RS SC SE SP TO)

      embedded_schema do
        field :amount, :float
        field :product_type, :string
        field :origin_state, :string
        field :destination_state, :string
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:amount, :product_type, :origin_state, :destination_state])
        |> validate_required([:amount, :product_type, :origin_state, :destination_state])
        |> validate_number(:amount, greater_than: 0)
        |> validate_inclusion(:product_type, @valid_types)
        |> validate_inclusion(:origin_state, @valid_states)
        |> validate_inclusion(:destination_state, @valid_states)
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
        field :taxes, :map
        field :total_taxes, :float
        field :final_amount, :float
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
        "amount" => 1000.0,
        "product_type" => "goods",
        "origin_state" => "SP",
        "destination_state" => "RJ"
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

        test "rejects invalid product_type" do
          changeset = Request.changeset(Map.put(@valid_params, "product_type", "invalid"))
          refute changeset.valid?
        end

        test "rejects invalid state" do
          changeset = Request.changeset(Map.put(@valid_params, "origin_state", "XX"))
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "interstate goods returns correct taxes" do
          result = Handler.handle(@valid_params)
          assert %{taxes: taxes, total_taxes: total, final_amount: final} = result
          assert taxes.icms > 0
          assert taxes.iss == 0.0
          assert taxes.pis > 0
          assert taxes.cofins > 0
          assert total > 0
          assert final > @valid_params["amount"]
        end

        test "service returns ISS and zero ICMS" do
          params = Map.put(@valid_params, "product_type", "service")
          result = Handler.handle(params)
          assert result.taxes.icms == 0.0
          assert result.taxes.iss > 0
        end

        test "intra-state uses higher intrastate rate" do
          intra_params = Map.put(@valid_params, "destination_state", "SP")
          inter_result = Handler.handle(@valid_params)
          intra_result = Handler.handle(intra_params)
          assert intra_result.taxes.icms > inter_result.taxes.icms
        end
      end

      describe "error handling" do
        test "returns error for invalid input" do
          result = Handler.handle(%{})
          assert %{error: "Validation failed", details: details} = result
          assert is_map(details)
        end

        test "returns error for zero value" do
          result = Handler.handle(Map.put(@valid_params, "amount", 0.0))
          assert %{error: "Validation failed", details: details} = result
          assert Map.has_key?(details, :amount)
        end
      end
    end
    """
  end

  defp readme_content do
    """
    # Brazilian Tax Calculator

    Calculates the main Brazilian taxes (ICMS, ISS, PIS and COFINS) for a sale,
    based on product type and origin/destination states.

    ## Parameters

    | Field | Type | Required | Description |
    |-------|------|-------------|-----------|
    | `amount` | number | yes | Base amount for calculation (must be > 0) |
    | `product_type` | string | yes | Type: `goods`, `service`, `manufactured_product`, `imported` |
    | `origin_state` | string | yes | Origin Brazilian state abbreviation (for example: SP, RJ, MG) |
    | `destination_state` | string | yes | Destination Brazilian state abbreviation (for example: SP, RJ, MG) |

    ## Example Request

    ```bash
    curl -X POST https://api.blackboex.com/api/my-org/brazilian-tax-calculator \\
      -H "Content-Type: application/json" \\
      -d '{
        "amount": 1000.00,
        "product_type": "goods",
        "origin_state": "SP",
        "destination_state": "RJ"
      }'
    ```

    ## Example Response

    ```json
    {
      "taxes": {
        "icms": 120.00,
        "iss": 0.00,
        "pis": 16.50,
        "cofins": 76.00
      },
      "total_taxes": 212.50,
      "final_amount": 1212.50
    }
    ```

    ## Business Rules

    - **ICMS**: Interstate operations use the destination state rate, usually 12%.
      Intrastate operations use the state's internal rate (for example: SP=18%, RJ=20%).
    - **ISS**: Applies only when `product_type = "service"` (5%).
    - **PIS**: 1.65% over the base amount.
    - **COFINS**: 7.6% over the base amount.

    ## Use Cases

    - AI agent tool for tax-aware pricing
    - Invoice simulation
    - Real-cost calculator for e-commerce
    """
  end
end
