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

  # Temporary relaxed defaults — these limits are intentionally above the
  # final business values so local dev, QA, and automated tests don't hit
  # the ceiling while the product is still in build-out. Tighten these
  # before launch. Per-environment overrides are supported via:
  #
  #     config :blackboex, Blackboex.Billing.Enforcement,
  #       free: %{max_apis: 10}
  #
  @default_limits %{
    free: %{max_apis: 100, max_invocations_per_day: 10_000, max_llm_generations_per_month: 500},
    pro: %{
      max_apis: 500,
      max_invocations_per_day: 500_000,
      max_llm_generations_per_month: 5_000
    },
    enterprise: %{
      max_apis: :unlimited,
      max_invocations_per_day: :unlimited,
      max_llm_generations_per_month: :unlimited
    }
  }

  @plan_atom_map %{"free" => :free, "pro" => :pro, "enterprise" => :enterprise}

  @spec limits() :: %{atom() => map()}
  defp limits do
    overrides = Application.get_env(:blackboex, __MODULE__, [])

    Map.new(@default_limits, fn {plan, defaults} ->
      plan_overrides = Keyword.get(overrides, plan, %{})
      {plan, Map.merge(defaults, plan_overrides)}
    end)
  end

  @spec effective_plan(Organization.t()) :: atom()
  def effective_plan(%Organization{id: org_id}) do
    case Billing.get_subscription(org_id) do
      %{status: "active", plan: plan} when is_binary(plan) ->
        Map.get(@plan_atom_map, plan, :free)

      _ ->
        :free
    end
  end

  @spec check_limit(Organization.t(), atom()) :: limit_check()
  def check_limit(%Organization{} = org, :create_api) do
    plan = effective_plan(org)
    limits = Map.fetch!(limits(), plan)

    case limits.max_apis do
      :unlimited ->
        {:ok, :unlimited}

      max ->
        current = count_apis(org.id)
        check(current, max, to_string(plan))
    end
  end

  def check_limit(%Organization{} = org, :create_flow) do
    plan = effective_plan(org)
    limits = Map.fetch!(limits(), plan)

    case limits.max_apis do
      :unlimited ->
        {:ok, :unlimited}

      max ->
        current = count_flows(org.id)
        check(current, max, to_string(plan))
    end
  end

  def check_limit(%Organization{} = org, :api_invocation) do
    plan = effective_plan(org)
    limits = Map.fetch!(limits(), plan)

    case limits.max_invocations_per_day do
      :unlimited ->
        {:ok, :unlimited}

      max ->
        current = Billing.count_usage_events_today(org.id, "api_invocation")
        check(current, max, to_string(plan))
    end
  end

  def check_limit(%Organization{} = org, :llm_generation) do
    plan = effective_plan(org)
    limits = Map.fetch!(limits(), plan)

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
    Map.fetch!(limits(), plan)
  end

  @spec get_usage_details(Organization.t()) :: %{
          plan: atom(),
          apis: %{used: non_neg_integer(), limit: non_neg_integer() | :unlimited, pct: float()},
          invocations_today: %{
            used: non_neg_integer(),
            limit: non_neg_integer() | :unlimited,
            pct: float()
          },
          llm_generations_month: %{
            used: non_neg_integer(),
            limit: non_neg_integer() | :unlimited,
            pct: float()
          }
        }
  def get_usage_details(%Organization{} = org) do
    plan = effective_plan(org)
    limits = get_limits(plan)

    api_count = count_apis(org.id)
    invocations = Billing.count_usage_events_today(org.id, "api_invocation")
    llm_gens = Billing.sum_monthly_usage(org.id, "llm_generation")

    %{
      plan: plan,
      apis: usage_detail(api_count, limits.max_apis),
      invocations_today: usage_detail(invocations, limits.max_invocations_per_day),
      llm_generations_month: usage_detail(llm_gens, limits.max_llm_generations_per_month)
    }
  end

  defp usage_detail(used, :unlimited), do: %{used: used, limit: :unlimited, pct: 0.0}

  defp usage_detail(used, limit),
    do: %{used: used, limit: limit, pct: Float.round(used / max(limit, 1) * 100, 1)}

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

  defp count_flows(organization_id) do
    Blackboex.Flows.Flow
    |> where([f], f.organization_id == ^organization_id)
    |> Repo.aggregate(:count)
  end
end
