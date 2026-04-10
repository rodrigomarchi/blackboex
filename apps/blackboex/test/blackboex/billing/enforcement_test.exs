defmodule Blackboex.Billing.EnforcementTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Billing
  alias Blackboex.Billing.Enforcement
  @moduletag :unit

  describe "effective_plan/1" do
    setup :create_user_and_org

    test "returns :free when no subscription exists", %{org: org} do
      assert :free = Enforcement.effective_plan(org)
    end

    test "returns :pro from active pro subscription", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "pro"})
      assert :pro = Enforcement.effective_plan(org)
    end

    test "returns :enterprise from active enterprise subscription", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "enterprise"})
      assert :enterprise = Enforcement.effective_plan(org)
    end

    test "returns :free when subscription is not active", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "pro", status: "canceled"})

      assert :free = Enforcement.effective_plan(org)
    end

    test "returns :free when subscription status is past_due", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "pro", status: "past_due"})

      assert :free = Enforcement.effective_plan(org)
    end
  end

  describe "check_limit/2 :create_api" do
    setup :create_user_and_org

    test "free plan allows up to 100 APIs when none exist", %{org: org} do
      assert {:ok, 100} = Enforcement.check_limit(org, :create_api)
    end

    test "free plan remaining decrements as APIs are created", %{org: org, user: user} do
      for _ <- 1..3, do: api_fixture(%{user: user, org: org})
      assert {:ok, 97} = Enforcement.check_limit(org, :create_api)
    end

    test "free plan returns limit_exceeded when at 100 APIs", %{org: org, user: user} do
      for _ <- 1..100, do: api_fixture(%{user: user, org: org})

      assert {:error, :limit_exceeded, details} = Enforcement.check_limit(org, :create_api)
      assert details.limit == 100
      assert details.current == 100
      assert details.plan == "free"
    end

    test "pro plan allows up to 500 APIs", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "pro"})
      assert {:ok, 500} = Enforcement.check_limit(org, :create_api)
    end

    test "enterprise plan is unlimited", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "enterprise"})
      assert {:ok, :unlimited} = Enforcement.check_limit(org, :create_api)
    end

    test "config override tightens free plan limit", %{org: org, user: user} do
      # Verify the runtime override hook works end-to-end without having to
      # create hundreds of fixtures just to cross the default ceiling.
      original = Application.get_env(:blackboex, Enforcement, [])
      Application.put_env(:blackboex, Enforcement, free: %{max_apis: 2})
      on_exit(fn -> Application.put_env(:blackboex, Enforcement, original) end)

      for _ <- 1..2, do: api_fixture(%{user: user, org: org})

      assert {:error, :limit_exceeded, details} = Enforcement.check_limit(org, :create_api)
      assert details.limit == 2
      assert details.current == 2
      assert details.plan == "free"
    end
  end

  describe "check_limit/2 :api_invocation" do
    setup :create_user_and_org

    test "free plan allows 10_000 invocations/day", %{org: org} do
      assert {:ok, 10_000} = Enforcement.check_limit(org, :api_invocation)
    end

    test "pro plan allows 500_000 invocations/day", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "pro"})
      assert {:ok, 500_000} = Enforcement.check_limit(org, :api_invocation)
    end

    test "enterprise plan is unlimited", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "enterprise"})
      assert {:ok, :unlimited} = Enforcement.check_limit(org, :api_invocation)
    end

    test "free plan returns limit_exceeded at the configured ceiling", %{org: org} do
      # Tighten the cap via runtime override so we don't have to insert
      # 10_000 usage events just to trip the check.
      original = Application.get_env(:blackboex, Enforcement, [])
      Application.put_env(:blackboex, Enforcement, free: %{max_invocations_per_day: 5})
      on_exit(fn -> Application.put_env(:blackboex, Enforcement, original) end)

      for _ <- 1..5 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "api_invocation"
          })
      end

      assert {:error, :limit_exceeded, details} = Enforcement.check_limit(org, :api_invocation)
      assert details.limit == 5
      assert details.current == 5
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

      assert {:ok, 9_995} = Enforcement.check_limit(org, :api_invocation)
    end
  end

  describe "check_limit/2 :llm_generation" do
    setup :create_user_and_org

    test "free plan allows 500 LLM generations/month", %{org: org} do
      assert {:ok, 500} = Enforcement.check_limit(org, :llm_generation)
    end

    test "pro plan allows 5_000 LLM generations/month", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "pro"})
      assert {:ok, 5_000} = Enforcement.check_limit(org, :llm_generation)
    end

    test "enterprise plan is unlimited", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "enterprise"})
      assert {:ok, :unlimited} = Enforcement.check_limit(org, :llm_generation)
    end

    test "free plan returns limit_exceeded at the configured ceiling", %{org: org} do
      original = Application.get_env(:blackboex, Enforcement, [])
      Application.put_env(:blackboex, Enforcement, free: %{max_llm_generations_per_month: 3})
      on_exit(fn -> Application.put_env(:blackboex, Enforcement, original) end)

      for _ <- 1..3 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "llm_generation"
          })
      end

      assert {:error, :limit_exceeded, details} = Enforcement.check_limit(org, :llm_generation)
      assert details.limit == 3
      assert details.current == 3
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

      assert {:ok, 490} = Enforcement.check_limit(org, :llm_generation)
    end
  end

  describe "get_limits/1" do
    test "returns correct limits for free plan" do
      limits = Enforcement.get_limits(:free)
      assert limits.max_apis == 100
      assert limits.max_invocations_per_day == 10_000
      assert limits.max_llm_generations_per_month == 500
    end

    test "returns correct limits for pro plan" do
      limits = Enforcement.get_limits(:pro)
      assert limits.max_apis == 500
      assert limits.max_invocations_per_day == 500_000
      assert limits.max_llm_generations_per_month == 5_000
    end

    test "returns :unlimited for enterprise plan" do
      limits = Enforcement.get_limits(:enterprise)
      assert limits.max_apis == :unlimited
      assert limits.max_invocations_per_day == :unlimited
      assert limits.max_llm_generations_per_month == :unlimited
    end

    test "config overrides merge on top of defaults" do
      original = Application.get_env(:blackboex, Enforcement, [])
      Application.put_env(:blackboex, Enforcement, free: %{max_apis: 7})
      on_exit(fn -> Application.put_env(:blackboex, Enforcement, original) end)

      limits = Enforcement.get_limits(:free)
      assert limits.max_apis == 7
      # Untouched keys keep their defaults
      assert limits.max_invocations_per_day == 10_000
      assert limits.max_llm_generations_per_month == 500
    end
  end

  describe "get_usage_details/1" do
    setup :create_user_and_org

    test "returns correct plan and zero usage for fresh org", %{org: org} do
      details = Enforcement.get_usage_details(org)

      assert details.plan == :free
      assert details.apis.used == 0
      assert details.apis.limit == 100
      assert details.apis.pct == 0.0
      assert details.invocations_today.used == 0
      assert details.invocations_today.limit == 10_000
      assert details.invocations_today.pct == 0.0
      assert details.llm_generations_month.used == 0
      assert details.llm_generations_month.limit == 500
      assert details.llm_generations_month.pct == 0.0
    end

    test "reflects api count in usage details", %{org: org, user: user} do
      for _ <- 1..3, do: api_fixture(%{user: user, org: org})

      details = Enforcement.get_usage_details(org)

      assert details.apis.used == 3
      assert details.apis.limit == 100
      assert details.apis.pct == 3.0
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
      assert details.invocations_today.limit == 10_000
      assert details.invocations_today.pct == 1.0
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
      assert details.llm_generations_month.limit == 500
      assert details.llm_generations_month.pct == 5.0
    end

    test "enterprise plan shows :unlimited limits with 0.0 pct", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "enterprise"})

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
      subscription_fixture(%{organization_id: org.id, plan: "pro"})

      details = Enforcement.get_usage_details(org)

      assert details.plan == :pro
      assert details.apis.limit == 500
      assert details.invocations_today.limit == 500_000
      assert details.llm_generations_month.limit == 5_000
    end
  end
end
