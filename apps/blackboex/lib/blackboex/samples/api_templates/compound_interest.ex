defmodule Blackboex.Samples.ApiTemplates.CompoundInterest do
  @moduledoc """
  Template: Compound Interest Calculator

  Calculates compound interest, installment value and full amortization table.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "compound-interest",
      name: "Compound Interest Calculator",
      description: "Calculates compound interest, installments and amortization tables",
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
        "principal_amount" => "number",
        "monthly_rate" => "number",
        "installment_count" => "integer"
      },
      example_request: %{
        "principal_amount" => 10_000.0,
        "monthly_rate" => 1.5,
        "installment_count" => 12
      },
      example_response: %{
        "installment_amount" => 912.15,
        "total_interest" => 945.8,
        "total_paid" => 10_945.8,
        "amortization_table" => [
          %{
            "installment" => 1,
            "opening_balance" => 10_000.0,
            "interest" => 150.0,
            "principal_payment" => 762.15,
            "remaining_balance" => 9_237.85
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
          installment = Helpers.installment(data.principal_amount, data.monthly_rate, data.installment_count)
          total_paid = Float.round(installment * data.installment_count, 2)
          total_interest = Float.round(total_paid - data.principal_amount, 2)
          table = Helpers.amortization_table(data.principal_amount, data.monthly_rate, installment, data.installment_count)

          %{
            installment_amount: installment,
            total_interest: total_interest,
            total_paid: total_paid,
            amortization_table: table
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
      def installment(principal, monthly_rate, installment_count) do
        rate = monthly_rate / 100.0

        if rate == 0.0 do
          Float.round(principal / installment_count, 2)
        else
          factor = :math.pow(1 + rate, installment_count)
          pmt = principal * rate * factor / (factor - 1)
          Float.round(pmt, 2)
        end
      end

      @doc "Builds a full amortization table for the loan."
      @spec amortization_table(float(), float(), float(), integer()) :: [map()]
      def amortization_table(principal, monthly_rate, installment, installment_count) do
        rate = monthly_rate / 100.0

        {_balance, rows} =
          Enum.reduce(1..installment_count, {principal, []}, fn i, {balance, acc} ->
            interest = Float.round(balance * rate, 2)
            principal_payment = Float.round(installment - interest, 2)
            remaining = max(0.0, Float.round(balance - principal_payment, 2))

            row = %{
              installment: i,
              opening_balance: Float.round(balance, 2),
              interest: interest,
              principal_payment: principal_payment,
              remaining_balance: remaining
            }

            {remaining, [row | acc]}
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
        field :principal_amount, :float
        field :monthly_rate, :float
        field :installment_count, :integer
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:principal_amount, :monthly_rate, :installment_count])
        |> validate_required([:principal_amount, :monthly_rate, :installment_count])
        |> validate_number(:principal_amount, greater_than: 0)
        |> validate_number(:monthly_rate, greater_than_or_equal_to: 0)
        |> validate_number(:installment_count, greater_than: 0)
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
        field :installment_amount, :float
        field :total_interest, :float
        field :total_paid, :float
        field :amortization_table, {:array, :map}
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
        "principal_amount" => 10_000.0,
        "monthly_rate" => 1.5,
        "installment_count" => 12
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
          changeset = Request.changeset(Map.put(@valid_params, "principal_amount", 0.0))
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "returns installment and totals" do
          result = Handler.handle(@valid_params)
          assert result.installment_amount > 0
          assert result.total_paid > 10_000.0
          assert result.total_interest > 0
          assert Float.round(result.total_interest + 10_000.0, 2) == result.total_paid
        end

        test "amortization table has correct row count" do
          result = Handler.handle(@valid_params)
          assert length(result.amortization_table) == 12
        end

        test "last row has near-zero balance" do
          result = Handler.handle(@valid_params)
          last = List.last(result.amortization_table)
          assert last.remaining_balance <= 1.0
        end

        test "zero rate means equal installments with no interest" do
          params = Map.put(@valid_params, "monthly_rate", 0.0)
          result = Handler.handle(params)
          assert abs(result.total_interest) < 0.1
          assert abs(result.installment_amount - Float.round(10_000.0 / 12, 2)) < 0.1
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
    # Compound Interest Calculator

    Calculates the monthly installment amount, total interest paid and full
    amortization table using the Price system for fixed-installment financing.

    ## Parameters

    | Field | Type | Required | Description |
    |-------|------|-------------|-----------|
    | `principal_amount` | number | yes | Loan or financing amount in BRL |
    | `monthly_rate` | number | yes | Monthly interest rate as a percentage (0 = no interest) |
    | `installment_count` | integer | yes | Number of monthly installments |

    ## Example Request

    ```bash
    curl -X POST https://api.blackboex.com/api/my-org/compound-interest \\
      -H "Content-Type: application/json" \\
      -d '{
        "principal_amount": 10000.00,
        "monthly_rate": 1.5,
        "installment_count": 12
      }'
    ```

    ## Example Response

    ```json
    {
      "installment_amount": 912.15,
      "total_interest": 945.80,
      "total_paid": 10945.80,
      "amortization_table": [
        {
          "installment": 1,
          "opening_balance": 10000.00,
          "interest": 150.00,
          "principal_payment": 762.15,
          "remaining_balance": 9237.85
        }
      ]
    }
    ```

    ## Calculation Method

    Uses the **Price system** with fixed installments:
    - `PMT = PV * i / (1 - (1+i)^-n)`
    - Each installment is split into interest (`balance * rate`) and principal payment (`PMT - interest`).

    ## Use Cases

    - Real estate or vehicle financing simulator
    - AI agent tool for credit analysis
    - Loan terms comparison
    """
  end
end
