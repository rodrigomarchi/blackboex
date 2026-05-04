defmodule Blackboex.Samples.ApiTemplates.CreditScoring do
  @moduledoc """
  Template: Credit Scoring

  Returns a simulated credit score based on income, age, employment
  history and restrictions.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "credit-scoring",
      name: "Credit Scoring",
      description: "Returns a simulated credit score from income, age and employment history",
      category: "AI Agent Tools",
      template_type: "computation",
      icon: "chart-bar",
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
        "monthly_income" => "number",
        "age" => "integer",
        "employment_months" => "integer",
        "has_restriction" => "boolean"
      },
      example_request: %{
        "monthly_income" => 5000.0,
        "age" => 35,
        "employment_months" => 24,
        "has_restriction" => false
      },
      example_response: %{
        "score" => 720,
        "band" => "good",
        "suggested_limit" => 15_000.0,
        "approved" => true
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
          %{"name" => "good profile returns high score and approved", "status" => "pass"},
          %{"name" => "restriction returns low score and rejected", "status" => "pass"},
          %{"name" => "young age reduces score", "status" => "pass"},
          %{"name" => "missing required fields returns error", "status" => "pass"},
          %{"name" => "negative income returns error", "status" => "pass"},
          %{"name" => "underage returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Calculates a simulated credit score."

      @doc "Processes request and returns credit score result or validation error."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          score = Helpers.calculate_score(data)
          band = Helpers.score_band(score)
          limit = Helpers.suggested_limit(score, data.monthly_income)
          approved = score >= 500 and not data.has_restriction
          %{score: score, band: band, suggested_limit: limit, approved: approved}
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
      @moduledoc "Credit score calculation helpers."

      @doc "Calculates credit score from validated input data."
      @spec calculate_score(map()) :: integer()
      def calculate_score(data) do
        base = 300

        income_pts =
          cond do
            data.monthly_income >= 10_000 -> 200
            data.monthly_income >= 5_000 -> 150
            data.monthly_income >= 2_000 -> 100
            data.monthly_income >= 1_000 -> 50
            true -> 0
          end

        age_pts =
          cond do
            data.age >= 40 -> 100
            data.age >= 30 -> 80
            data.age >= 25 -> 60
            data.age >= 18 -> 30
            true -> 0
          end

        employment_pts =
          cond do
            data.employment_months >= 60 -> 150
            data.employment_months >= 24 -> 100
            data.employment_months >= 12 -> 60
            data.employment_months >= 6 -> 30
            true -> 0
          end

        restriction_penalty = if data.has_restriction, do: -200, else: 0
        score = base + income_pts + age_pts + employment_pts + restriction_penalty
        min(max(score, 0), 1000)
      end

      @doc "Returns the score band label for a given score."
      @spec score_band(integer()) :: String.t()
      def score_band(score) do
        cond do
          score >= 800 -> "excellent"
          score >= 700 -> "good"
          score >= 500 -> "fair"
          score >= 300 -> "poor"
          true -> "very_poor"
        end
      end

      @doc "Returns suggested credit limit based on score and monthly income."
      @spec suggested_limit(integer(), float()) :: float()
      def suggested_limit(score, monthly_income) do
        multiplier =
          cond do
            score >= 800 -> 5.0
            score >= 700 -> 3.0
            score >= 500 -> 1.5
            true -> 0.0
          end

        Float.round(monthly_income * multiplier, 2)
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Input schema for the credit scoring API."
      use Blackboex.Schema

      embedded_schema do
        field :monthly_income, :float
        field :age, :integer
        field :employment_months, :integer
        field :has_restriction, :boolean
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:monthly_income, :age, :employment_months, :has_restriction])
        |> validate_required([:monthly_income, :age, :employment_months, :has_restriction])
        |> validate_number(:monthly_income, greater_than: 0)
        |> validate_number(:age, greater_than_or_equal_to: 18)
        |> validate_number(:employment_months, greater_than_or_equal_to: 0)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Output schema for the credit scoring API."
      use Blackboex.Schema

      embedded_schema do
        field :score, :integer
        field :band, :string
        field :suggested_limit, :float
        field :approved, :boolean
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the credit scoring handler."
      use ExUnit.Case

      @good_profile %{
        "monthly_income" => 5000.0,
        "age" => 35,
        "employment_months" => 24,
        "has_restriction" => false
      }

      describe "Request changeset validation" do
        test "accepts valid input" do
          changeset = Request.changeset(@good_profile)
          assert changeset.valid?
        end

        test "rejects missing fields" do
          changeset = Request.changeset(%{})
          refute changeset.valid?
        end

        test "rejects underage" do
          changeset = Request.changeset(Map.put(@good_profile, "age", 17))
          refute changeset.valid?
        end

        test "rejects negative income" do
          changeset = Request.changeset(Map.put(@good_profile, "monthly_income", -100.0))
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "good profile returns score >= 500 and approved" do
          result = Handler.handle(@good_profile)
          assert result.score >= 500
          assert result.approved == true
          assert result.suggested_limit > 0
          assert result.band in ["good", "excellent", "fair"]
        end

        test "restriction returns not approved" do
          result = Handler.handle(Map.put(@good_profile, "has_restriction", true))
          assert result.approved == false
        end

        test "high income and long employment raises score" do
          params = Map.merge(@good_profile, %{
            "monthly_income" => 15_000.0,
            "age" => 45,
            "employment_months" => 72
          })
          result = Handler.handle(params)
          assert result.score >= 700
          assert result.band in ["good", "excellent"]
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
    # Credit Scoring

    Returns a simulated credit score (0-1000) based on monthly income, age,
    employment history and restriction status, plus a suggested credit limit.

    ## Parameters

    | Field | Type | Required | Description |
    |-------|------|-------------|-----------|
    | `monthly_income` | number | yes | Gross monthly income in BRL (must be > 0) |
    | `age` | integer | yes | Age in years (minimum 18) |
    | `employment_months` | integer | yes | Months in current employment (>= 0) |
    | `has_restriction` | boolean | yes | Whether the person has credit restrictions |

    ## Example Request

    ```bash
    curl -X POST https://api.blackboex.com/api/my-org/credit-scoring \\
      -H "Content-Type: application/json" \\
      -d '{
        "monthly_income": 5000.00,
        "age": 35,
        "employment_months": 24,
        "has_restriction": false
      }'
    ```

    ## Example Response

    ```json
    {
      "score": 720,
      "band": "good",
      "suggested_limit": 15000.00,
      "approved": true
    }
    ```

    ## Score Bands

    | Band | Score | Description |
    |-------|-------|-----------|
    | excellent | 800-1000 | Immediate approval, maximum limit |
    | good | 700-799 | Approved, good limit |
    | fair | 500-699 | Approved with reduced limit |
    | poor | 300-499 | Rejected |
    | very_poor | 0-299 | Rejected, severe restrictions |

    ## Use Cases

    - AI agent tool for credit prequalification
    - Financing simulator
    - Initial screening for credit-granting processes
    """
  end
end
