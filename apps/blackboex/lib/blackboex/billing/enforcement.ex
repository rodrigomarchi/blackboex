defmodule Blackboex.Billing.Enforcement do
  @moduledoc """
  Enforces plan-based usage limits.
  Checks are performed before resource creation, API invocation, and LLM generation.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Billing
  alias Blackboex.Organizations.Organization
  alias Blackboex.Repo

  @type limit_check ::
          {:ok, non_neg_integer()}
          | {:error, :limit_exceeded,
             %{
               limit: non_neg_integer() | :unlimited,
               current: non_neg_integer(),
               plan: String.t()
             }}

  @limits %{
    free: %{max_apis: 10, max_invocations_per_day: 1_000, max_llm_generations_per_month: 50},
    pro: %{max_apis: 50, max_invocations_per_day: 50_000, max_llm_generations_per_month: 500},
    enterprise: %{
      max_apis: :unlimited,
      max_invocations_per_day: :unlimited,
      max_llm_generations_per_month: :unlimited
    }
  }

  @spec check_limit(Organization.t(), atom()) :: limit_check()
  def check_limit(%Organization{plan: plan} = org, :create_api) do
    limits = Map.fetch!(@limits, plan)

    case limits.max_apis do
      :unlimited ->
        {:ok, :unlimited}

      max ->
        current = count_apis(org.id)
        check(current, max, to_string(plan))
    end
  end

  def check_limit(%Organization{plan: plan} = org, :api_invocation) do
    limits = Map.fetch!(@limits, plan)

    case limits.max_invocations_per_day do
      :unlimited ->
        {:ok, :unlimited}

      max ->
        current = Billing.count_usage_events_today(org.id, "api_invocation")
        check(current, max, to_string(plan))
    end
  end

  def check_limit(%Organization{plan: plan} = org, :llm_generation) do
    limits = Map.fetch!(@limits, plan)

    case limits.max_llm_generations_per_month do
      :unlimited ->
        {:ok, :unlimited}

      max ->
        current = Billing.sum_monthly_usage(org.id, "llm_generation")
        check(current, max, to_string(plan))
    end
  end

  @spec get_limits(atom()) :: map()
  def get_limits(plan) do
    Map.fetch!(@limits, plan)
  end

  defp check(current, max, _plan) when current < max do
    {:ok, max - current}
  end

  defp check(current, max, plan) do
    {:error, :limit_exceeded, %{limit: max, current: current, plan: plan}}
  end

  defp count_apis(organization_id) do
    Blackboex.Apis.Api
    |> where([a], a.organization_id == ^organization_id)
    |> Repo.aggregate(:count)
  end
end
