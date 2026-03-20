defmodule Blackboex.Billing.EnforcementTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Billing
  alias Blackboex.Billing.Enforcement
  alias Blackboex.Organizations

  import Blackboex.AccountsFixtures

  @moduletag :unit

  defp create_org(_context) do
    user = user_fixture()
    [org] = Organizations.list_user_organizations(user)
    %{org: org, user: user}
  end

  describe "check_limit/2 :create_api" do
    setup [:create_org]

    test "free plan allows up to 10 APIs", %{org: org} do
      assert {:ok, 10} = Enforcement.check_limit(org, :create_api)
    end

    test "pro plan allows up to 50 APIs", %{org: org} do
      org = %{org | plan: :pro}
      assert {:ok, 50} = Enforcement.check_limit(org, :create_api)
    end

    test "enterprise plan is unlimited", %{org: org} do
      org = %{org | plan: :enterprise}
      assert {:ok, :unlimited} = Enforcement.check_limit(org, :create_api)
    end
  end

  describe "check_limit/2 :api_invocation" do
    setup [:create_org]

    test "free plan allows 1000 invocations/day", %{org: org} do
      assert {:ok, 1000} = Enforcement.check_limit(org, :api_invocation)
    end

    test "returns limit_exceeded when over limit", %{org: org} do
      # Create 1000 usage events to hit the limit
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
  end

  describe "check_limit/2 :llm_generation" do
    setup [:create_org]

    test "free plan allows 50 LLM generations/month", %{org: org} do
      assert {:ok, 50} = Enforcement.check_limit(org, :llm_generation)
    end

    test "pro plan allows 500 LLM generations/month", %{org: org} do
      org = %{org | plan: :pro}
      assert {:ok, 500} = Enforcement.check_limit(org, :llm_generation)
    end
  end

  describe "get_limits/1" do
    test "returns limits for each plan" do
      assert %{max_apis: 10} = Enforcement.get_limits(:free)
      assert %{max_apis: 50} = Enforcement.get_limits(:pro)
      assert %{max_apis: :unlimited} = Enforcement.get_limits(:enterprise)
    end
  end
end
