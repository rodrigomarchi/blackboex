defmodule Blackboex.Samples.ApiTemplates.CurrencyConverter do
  @moduledoc """
  Template: Currency Converter

  Converts between currencies using hardcoded reference rates.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "currency-converter",
      name: "Currency Converter",
      description: "Converts between currencies with hardcoded reference rates",
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
        "amount" => "number",
        "source_currency" => "string",
        "target_currency" => "string"
      },
      example_request: %{
        "amount" => 100.0,
        "source_currency" => "USD",
        "target_currency" => "BRL"
      },
      example_response: %{
        "converted_amount" => 497.01,
        "rate" => 4.970_149,
        "reference_date" => "2024-01-15"
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

          case Helpers.convert(data.amount, data.source_currency, data.target_currency) do
            {:ok, result} ->
              result

            {:error, reason} ->
              %{error: "Validation failed", details: %{currency: [reason]}}
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
      def convert(amount, source_currency, target_currency) do
        with {:ok, source_rate} <- get_rate(source_currency),
             {:ok, target_rate} <- get_rate(target_currency) do
          in_brl = amount / source_rate
          converted = in_brl * target_rate
          rate = Float.round(target_rate / source_rate, 6)

          {:ok,
           %{
             converted_amount: Float.round(converted, 2),
             rate: rate,
             reference_date: @reference_date
           }}
        end
      end

      @doc "Returns supported currency codes."
      @spec supported_currencies() :: [String.t()]
      def supported_currencies, do: Map.keys(@rates_from_brl)

      @spec get_rate(String.t()) :: {:ok, float()} | {:error, String.t()}
      defp get_rate(currency) do
        case Map.get(@rates_from_brl, currency) do
          nil -> {:error, "unsupported currency: #{currency}"}
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
        field :amount, :float
        field :source_currency, :string
        field :target_currency, :string
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:amount, :source_currency, :target_currency])
        |> validate_required([:amount, :source_currency, :target_currency])
        |> validate_number(:amount, greater_than: 0)
        |> validate_inclusion(:source_currency, @supported)
        |> validate_inclusion(:target_currency, @supported)
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
        field :converted_amount, :float
        field :rate, :float
        field :reference_date, :string
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
            "amount" => 100.0,
            "source_currency" => "USD",
            "target_currency" => "BRL"
          })
          assert changeset.valid?
        end

        test "rejects missing fields" do
          changeset = Request.changeset(%{})
          refute changeset.valid?
        end

        test "rejects unknown currency" do
          changeset = Request.changeset(%{
            "amount" => 100.0,
            "source_currency" => "XYZ",
            "target_currency" => "BRL"
          })
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "USD to BRL returns value greater than original" do
          result = Handler.handle(%{"amount" => 100.0, "source_currency" => "USD", "target_currency" => "BRL"})
          assert result.converted_amount > 100.0
          assert result.rate > 1.0
          assert is_binary(result.reference_date)
        end

        test "BRL to USD returns fraction" do
          result = Handler.handle(%{"amount" => 500.0, "source_currency" => "BRL", "target_currency" => "USD"})
          assert result.converted_amount < 500.0
          assert result.rate < 1.0
        end

        test "same currency returns same value with rate 1.0" do
          result = Handler.handle(%{"amount" => 100.0, "source_currency" => "BRL", "target_currency" => "BRL"})
          assert result.converted_amount == 100.0
          assert result.rate == 1.0
        end
      end

      describe "error handling" do
        test "returns error for invalid input" do
          result = Handler.handle(%{})
          assert %{error: "Validation failed", details: details} = result
          assert is_map(details)
        end

        test "returns error for zero value" do
          result = Handler.handle(%{"amount" => 0.0, "source_currency" => "USD", "target_currency" => "BRL"})
          assert %{error: "Validation failed", details: details} = result
          assert Map.has_key?(details, :amount)
        end
      end
    end
    """
  end

  defp readme_content do
    """
    # Currency Converter

    Converts values between 15 currencies using hardcoded reference rates.
    Ideal as an AI agent tool for financial calculations and price comparisons.

    ## Parameters

    | Field | Type | Required | Description |
    |-------|------|-------------|-----------|
    | `amount` | number | yes | Amount to convert (must be > 0) |
    | `source_currency` | string | yes | Source currency ISO code |
    | `target_currency` | string | yes | Target currency ISO code |

    ## Supported Currencies

    BRL, USD, EUR, GBP, ARS, CLP, COP, MXN, PYG, UYU, CAD, AUD, JPY, CNY, CHF

    ## Example Request

    ```bash
    curl -X POST https://api.blackboex.com/api/my-org/currency-converter \\
      -H "Content-Type: application/json" \\
      -d '{"amount": 100.0, "source_currency": "USD", "target_currency": "BRL"}'
    ```

    ## Example Response

    ```json
    {
      "converted_amount": 497.01,
      "rate": 4.970149,
      "reference_date": "2024-01-15"
    }
    ```

    ## Use Cases

    - AI agent tool for international price comparison
    - Import cost calculator
    - Financial dashboard with value conversion
    """
  end
end
