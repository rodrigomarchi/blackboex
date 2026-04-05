defmodule Blackboex.Billing.EnforcementTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Apis
  alias Blackboex.Billing
  alias Blackboex.Billing.{Enforcement, Subscription}
  alias Blackboex.Organizations

  import Blackboex.AccountsFixtures

  @moduletag :unit

  defp create_org(_context) do
    user = user_fixture()
    [org] = Organizations.list_user_organizations(user)
    %{org: org, user: user}
  end

  defp create_subscription(org, plan) do
    %Subscription{}
    |> Subscription.changeset(%{
      organization_id: org.id,
      plan: plan,
      status: "active"
    })
    |> Repo.insert!()
  end

  defp create_api(org, user, name \\ nil) do
    api_name = name || "API #{System.unique_integer([:positive])}"

    {:ok, api} =
      Apis.create_api(%{
        name: api_name,
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id
      })

    api
  end

  describe "effective_plan/1" do
    setup [:create_org]

    test "returns :free when no subscription exists", %{org: org} do
      assert :free = Enforcement.effective_plan(org)
    end

    test "returns :pro from active pro subscription", %{org: org} do
      create_subscription(org, "pro")
      assert :pro = Enforcement.effective_plan(org)
    end

    test "returns :enterprise from active enterprise subscription", %{org: org} do
      create_subscription(org, "enterprise")
      assert :enterprise = Enforcement.effective_plan(org)
    end

    test "returns :free when subscription is not active", %{org: org} do
      %Subscription{}
      |> Subscription.changeset(%{
        organization_id: org.id,
        plan: "pro",
        status: "canceled"
      })
      |> Repo.insert!()

      assert :free = Enforcement.effective_plan(org)
    end

    test "returns :free when subscription status is past_due", %{org: org} do
      %Subscription{}
      |> Subscription.changeset(%{
        organization_id: org.id,
        plan: "pro",
        status: "past_due"
      })
      |> Repo.insert!()

      assert :free = Enforcement.effective_plan(org)
    end
  end

  describe "check_limit/2 :create_api" do
    setup [:create_org]

    test "free plan allows up to 10 APIs when none exist", %{org: org} do
      assert {:ok, 10} = Enforcement.check_limit(org, :create_api)
    end

    test "free plan remaining decrements as APIs are created", %{org: org, user: user} do
      for _ <- 1..3, do: create_api(org, user)
      assert {:ok, 7} = Enforcement.check_limit(org, :create_api)
    end

    test "free plan returns limit_exceeded when at 10 APIs", %{org: org, user: user} do
      for _ <- 1..10, do: create_api(org, user)

      assert {:error, :limit_exceeded, details} = Enforcement.check_limit(org, :create_api)
      assert details.limit == 10
      assert details.current == 10
      assert details.plan == "free"
    end

    test "pro plan allows up to 50 APIs", %{org: org} do
      create_subscription(org, "pro")
      assert {:ok, 50} = Enforcement.check_limit(org, :create_api)
    end

    test "pro plan returns limit_exceeded when at 50 APIs", %{org: org, user: user} do
      create_subscription(org, "pro")
      for _ <- 1..50, do: create_api(org, user)

      assert {:error, :limit_exceeded, details} = Enforcement.check_limit(org, :create_api)
      assert details.limit == 50
      assert details.current == 50
      assert details.plan == "pro"
    end

    test "enterprise plan is unlimited", %{org: org} do
      create_subscription(org, "enterprise")
      assert {:ok, :unlimited} = Enforcement.check_limit(org, :create_api)
    end
  end

  describe "check_limit/2 :api_invocation" do
    setup [:create_org]

    test "free plan allows 1000 invocations/day", %{org: org} do
      assert {:ok, 1000} = Enforcement.check_limit(org, :api_invocation)
    end

    test "pro plan allows 50_000 invocations/day", %{org: org} do
      create_subscription(org, "pro")
      assert {:ok, 50_000} = Enforcement.check_limit(org, :api_invocation)
    end

    test "enterprise plan is unlimited", %{org: org} do
      create_subscription(org, "enterprise")
      assert {:ok, :unlimited} = Enforcement.check_limit(org, :api_invocation)
    end

    test "free plan returns limit_exceeded when at 1000 invocations", %{org: org} do
      for _ <- 1..1000 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "api_invocation"
          })
      end

      assert {:error, :limit_exceeded, details} = Enforcement.check_limit(org, :api_invocation)
      assert details.limit == 1000
      assert details.current == 1000
      assert details.plan == "free"
    end

    test "remaining count decrements with usage", %{org: org} do
      for _ <- 1..5 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "api_invocation"
          })
      end

      assert {:ok, 995} = Enforcement.check_limit(org, :api_invocation)
    end
  end

  describe "check_limit/2 :llm_generation" do
    setup [:create_org]

    test "free plan allows 50 LLM generations/month", %{org: org} do
      assert {:ok, 50} = Enforcement.check_limit(org, :llm_generation)
    end

    test "pro plan allows 500 LLM generations/month", %{org: org} do
      create_subscription(org, "pro")
      assert {:ok, 500} = Enforcement.check_limit(org, :llm_generation)
    end

    test "enterprise plan is unlimited", %{org: org} do
      create_subscription(org, "enterprise")
      assert {:ok, :unlimited} = Enforcement.check_limit(org, :llm_generation)
    end

    test "free plan returns limit_exceeded when at 50 LLM generations", %{org: org} do
      for _ <- 1..50 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "llm_generation"
          })
      end

      assert {:error, :limit_exceeded, details} = Enforcement.check_limit(org, :llm_generation)
      assert details.limit == 50
      assert details.current == 50
      assert details.plan == "free"
    end

    test "remaining count decrements with usage", %{org: org} do
      for _ <- 1..10 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "llm_generation"
          })
      end

      assert {:ok, 40} = Enforcement.check_limit(org, :llm_generation)
    end
  end

  describe "get_limits/1" do
    test "returns correct limits for free plan" do
      limits = Enforcement.get_limits(:free)
      assert limits.max_apis == 10
      assert limits.max_invocations_per_day == 1_000
      assert limits.max_llm_generations_per_month == 50
    end

    test "returns correct limits for pro plan" do
      limits = Enforcement.get_limits(:pro)
      assert limits.max_apis == 50
      assert limits.max_invocations_per_day == 50_000
      assert limits.max_llm_generations_per_month == 500
    end

    test "returns :unlimited for enterprise plan" do
      limits = Enforcement.get_limits(:enterprise)
      assert limits.max_apis == :unlimited
      assert limits.max_invocations_per_day == :unlimited
      assert limits.max_llm_generations_per_month == :unlimited
    end
  end

  describe "get_usage_details/1" do
    setup [:create_org]

    test "returns correct plan and zero usage for fresh org", %{org: org} do
      details = Enforcement.get_usage_details(org)

      assert details.plan == :free
      assert details.apis.used == 0
      assert details.apis.limit == 10
      assert details.apis.pct == 0.0
      assert details.invocations_today.used == 0
      assert details.invocations_today.limit == 1_000
      assert details.invocations_today.pct == 0.0
      assert details.llm_generations_month.used == 0
      assert details.llm_generations_month.limit == 50
      assert details.llm_generations_month.pct == 0.0
    end

    test "reflects api count in usage details", %{org: org, user: user} do
      for _ <- 1..3, do: create_api(org, user)

      details = Enforcement.get_usage_details(org)

      assert details.apis.used == 3
      assert details.apis.limit == 10
      assert details.apis.pct == 30.0
    end

    test "reflects invocation usage in usage details", %{org: org} do
      for _ <- 1..100 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "api_invocation"
          })
      end

      details = Enforcement.get_usage_details(org)

      assert details.invocations_today.used == 100
      assert details.invocations_today.limit == 1_000
      assert details.invocations_today.pct == 10.0
    end

    test "reflects llm generation usage in usage details", %{org: org} do
      for _ <- 1..25 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "llm_generation"
          })
      end

      details = Enforcement.get_usage_details(org)

      assert details.llm_generations_month.used == 25
      assert details.llm_generations_month.limit == 50
      assert details.llm_generations_month.pct == 50.0
    end

    test "enterprise plan shows :unlimited limits with 0.0 pct", %{org: org} do
      create_subscription(org, "enterprise")

      details = Enforcement.get_usage_details(org)

      assert details.plan == :enterprise
      assert details.apis.limit == :unlimited
      assert details.apis.pct == 0.0
      assert details.invocations_today.limit == :unlimited
      assert details.invocations_today.pct == 0.0
      assert details.llm_generations_month.limit == :unlimited
      assert details.llm_generations_month.pct == 0.0
    end

    test "pro plan shows correct limits", %{org: org} do
      create_subscription(org, "pro")

      details = Enforcement.get_usage_details(org)

      assert details.plan == :pro
      assert details.apis.limit == 50
      assert details.invocations_today.limit == 50_000
      assert details.llm_generations_month.limit == 500
    end
  end
end
