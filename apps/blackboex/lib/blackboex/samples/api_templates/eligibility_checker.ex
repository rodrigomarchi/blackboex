defmodule Blackboex.Samples.ApiTemplates.EligibilityChecker do
  @moduledoc """
  Template: Eligibility Checker

  Checks eligibility for a service based on business rules:
  age, income, state and plan type.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "eligibility-checker",
      name: "Eligibility Checker",
      description: "Checks service plan eligibility from configured business rules",
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
        "age" => "integer",
        "income" => "number",
        "state" => "string",
        "plan_type" => "string"
      },
      example_request: %{
        "age" => 30,
        "income" => 3000.0,
        "state" => "SP",
        "plan_type" => "basic"
      },
      example_response: %{
        "eligible" => true,
        "reason" => "all criteria met",
        "available_plans" => ["basic", "intermediate"]
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
          %{"name" => "eligible profile returns eligible true", "status" => "pass"},
          %{"name" => "underage returns not eligible", "status" => "pass"},
          %{"name" => "low income for premium returns not eligible", "status" => "pass"},
          %{"name" => "unavailable state returns not eligible", "status" => "pass"},
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
          {eligible, reason} = Helpers.check_eligibility(data)
          plans = if eligible, do: Helpers.available_plans(data), else: []
          %{eligible: eligible, reason: reason, available_plans: plans}
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

      @min_age %{"basic" => 18, "intermediate" => 18, "premium" => 21, "business" => 18}
      @min_income %{
        "basic" => 1_000.0,
        "intermediate" => 2_000.0,
        "premium" => 5_000.0,
        "business" => 3_000.0
      }

      @unavailable_states %{
        "premium" => ["AC", "RR", "AP"],
        "business" => ["AC", "RR"]
      }

      @doc "Returns {eligible?, reason} for the given applicant data."
      @spec check_eligibility(map()) :: {boolean(), String.t()}
      def check_eligibility(data) do
        plan = data.plan_type

        cond do
          data.age < Map.get(@min_age, plan, 18) ->
            {false, "minimum age not met for plan #{plan}"}

          data.income < Map.get(@min_income, plan, 0.0) ->
            {false, "insufficient income for plan #{plan}"}

          data.state in Map.get(@unavailable_states, plan, []) ->
            {false, "plan #{plan} is not available in state #{data.state}"}

          true ->
            {true, "all criteria met"}
        end
      end

      @doc "Returns list of plan names the applicant qualifies for."
      @spec available_plans(map()) :: [String.t()]
      def available_plans(data) do
        all_plans = ["basic", "intermediate", "premium", "business"]

        Enum.filter(all_plans, fn plan ->
          age_ok = data.age >= Map.get(@min_age, plan, 18)
          income_ok = data.income >= Map.get(@min_income, plan, 0.0)
          state_ok = data.state not in Map.get(@unavailable_states, plan, [])
          age_ok and income_ok and state_ok
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

      @valid_states ~w(AC AL AM AP BA CE DF ES GO MA MG MS MT PA PB PE PI PR RJ RN RO RR RS SC SE SP TO)
      @valid_plans ["basic", "intermediate", "premium", "business"]

      embedded_schema do
        field :age, :integer
        field :income, :float
        field :state, :string
        field :plan_type, :string
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:age, :income, :state, :plan_type])
        |> validate_required([:age, :income, :state, :plan_type])
        |> validate_number(:age, greater_than_or_equal_to: 0)
        |> validate_number(:income, greater_than_or_equal_to: 0)
        |> validate_inclusion(:state, @valid_states)
        |> validate_inclusion(:plan_type, @valid_plans)
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
        field :eligible, :boolean
        field :reason, :string
        field :available_plans, {:array, :string}
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
        "age" => 30,
        "income" => 3000.0,
        "state" => "SP",
        "plan_type" => "basic"
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

        test "rejects invalid state" do
          changeset = Request.changeset(Map.put(@valid_params, "state", "XX"))
          refute changeset.valid?
        end

        test "rejects invalid plan_type" do
          changeset = Request.changeset(Map.put(@valid_params, "plan_type", "gold"))
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "eligible profile returns eligible true with plans" do
          result = Handler.handle(@valid_params)
          assert result.eligible == true
          assert is_binary(result.reason)
          assert is_list(result.available_plans)
          assert "basic" in result.available_plans
        end

        test "underage for premium returns not eligible" do
          params = Map.merge(@valid_params, %{"age" => 19, "plan_type" => "premium", "income" => 6000.0})
          result = Handler.handle(params)
          assert result.eligible == false
          assert String.contains?(result.reason, "age")
        end

        test "low income for premium returns not eligible" do
          params = Map.merge(@valid_params, %{"plan_type" => "premium", "income" => 2000.0})
          result = Handler.handle(params)
          assert result.eligible == false
          assert String.contains?(result.reason, "income")
        end

        test "unavailable state for premium returns not eligible" do
          params = Map.merge(@valid_params, %{
            "plan_type" => "premium",
            "state" => "AC",
            "income" => 6000.0,
            "age" => 25
          })
          result = Handler.handle(params)
          assert result.eligible == false
          assert String.contains?(result.reason, "state")
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
    # Eligibility Checker

    Checks whether a customer is eligible for a service plan based on configured
    business rules: minimum age, minimum income and state availability.

    ## Parameters

    | Field | Type | Required | Description |
    |-------|------|-------------|-----------|
    | `age` | integer | yes | Applicant age in years |
    | `income` | number | yes | Monthly income in BRL |
    | `state` | string | yes | Residence state (for example: SP, RJ) |
    | `plan_type` | string | yes | Desired plan: `basic`, `intermediate`, `premium`, `business` |

    ## Plans and Requirements

    | Plan | Minimum Age | Minimum Income | State Restrictions |
    |-------|-------------|-------------|-----------------|
    | basic | 18 | BRL 1,000 | none |
    | intermediate | 18 | BRL 2,000 | none |
    | premium | 21 | BRL 5,000 | unavailable in AC, RR, AP |
    | business | 18 | BRL 3,000 | unavailable in AC, RR |

    ## Example Request

    ```bash
    curl -X POST https://api.blackboex.com/api/my-org/eligibility-checker \\
      -H "Content-Type: application/json" \\
      -d '{
        "age": 30,
        "income": 3000.00,
        "state": "SP",
        "plan_type": "basic"
      }'
    ```

    ## Example Response

    ```json
    {
      "eligible": true,
      "reason": "all criteria met",
      "available_plans": ["basic", "intermediate"]
    }
    ```

    ## Use Cases

    - AI agent tool for customer prequalification
    - Sign-up form with real-time validation
    - Plan recommendation system
    """
  end
end
