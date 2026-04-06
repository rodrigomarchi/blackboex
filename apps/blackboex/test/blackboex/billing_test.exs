defmodule Blackboex.BillingTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Billing
  alias Blackboex.Organizations

  import Mox

  @moduletag :unit

  describe "get_subscription/1" do
    setup :create_user_and_org

    test "returns nil when no subscription exists", %{org: org} do
      assert Billing.get_subscription(org.id) == nil
    end

    test "returns subscription when it exists", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "pro"})

      sub = Billing.get_subscription(org.id)
      assert sub.plan == "pro"
      assert sub.organization_id == org.id
    end
  end

  describe "create_checkout_session/4" do
    setup :create_user_and_org

    test "calls Stripe client and returns URL", %{org: org} do
      Blackboex.Billing.StripeClientMock
      |> expect(:create_checkout_session, fn params ->
        assert params.price_id == "price_pro_monthly"
        assert params.metadata["organization_id"] == org.id
        assert params.metadata["plan"] == "pro"
        {:ok, %{id: "cs_test123", url: "https://checkout.stripe.com/test"}}
      end)

      assert {:ok, %{url: url}} =
               Billing.create_checkout_session(
                 org,
                 "pro",
                 "https://example.com/success",
                 "https://example.com/cancel"
               )

      assert url == "https://checkout.stripe.com/test"
    end

    test "returns error when Stripe fails", %{org: org} do
      Blackboex.Billing.StripeClientMock
      |> expect(:create_checkout_session, fn _params ->
        {:error, "stripe_error"}
      end)

      assert {:error, "stripe_error"} =
               Billing.create_checkout_session(
                 org,
                 "pro",
                 "https://example.com/success",
                 "https://example.com/cancel"
               )
    end
  end

  describe "create_portal_session/2" do
    setup :create_user_and_org

    test "returns portal URL when subscription exists", %{org: org} do
      subscription_fixture(%{
        organization_id: org.id,
        stripe_customer_id: "cus_test123",
        plan: "pro"
      })

      Blackboex.Billing.StripeClientMock
      |> expect(:create_portal_session, fn "cus_test123", return_url ->
        assert return_url == "https://example.com/billing"
        {:ok, %{url: "https://billing.stripe.com/session/test"}}
      end)

      assert {:ok, %{url: url}} =
               Billing.create_portal_session(org, "https://example.com/billing")

      assert url == "https://billing.stripe.com/session/test"
    end

    test "returns error when no subscription exists", %{org: org} do
      assert {:error, :no_subscription} =
               Billing.create_portal_session(org, "https://example.com/billing")
    end
  end

  describe "create_or_update_subscription/1" do
    setup :create_user_and_org

    test "creates new subscription and syncs org plan", %{org: org} do
      attrs = %{
        organization_id: org.id,
        stripe_customer_id: "cus_test",
        stripe_subscription_id: "sub_test",
        plan: "pro",
        status: "active"
      }

      assert {:ok, sub} = Billing.create_or_update_subscription(attrs)
      assert sub.plan == "pro"
      assert sub.organization_id == org.id

      # Verify org plan was synced
      updated_org = Organizations.get_organization!(org.id)
      assert updated_org.plan == :pro
    end

    test "returns changeset error when organization does not exist", %{org: org} do
      nonexistent_org_id = Ecto.UUID.generate()

      attrs = %{
        organization_id: nonexistent_org_id,
        stripe_customer_id: "cus_ghost",
        stripe_subscription_id: "sub_ghost",
        plan: "pro",
        status: "active"
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               Billing.create_or_update_subscription(attrs)

      assert {:organization_id, {"does not exist", _}} = hd(changeset.errors)

      # Verify no subscription was created
      assert Billing.get_subscription(org.id) == nil
    end

    test "updates existing subscription", %{org: org} do
      subscription_fixture(%{organization_id: org.id, plan: "pro"})

      attrs = %{
        organization_id: org.id,
        plan: "enterprise",
        status: "active"
      }

      assert {:ok, sub} = Billing.create_or_update_subscription(attrs)
      assert sub.plan == "enterprise"

      # Verify org plan was synced
      updated_org = Organizations.get_organization!(org.id)
      assert updated_org.plan == :enterprise
    end
  end

  describe "record_usage_event/1 and count_usage_events_today/2" do
    setup :create_user_and_org

    test "count returns 0 when no events recorded", %{org: org} do
      assert Billing.count_usage_events_today(org.id, "api_invocation") == 0
    end

    test "count returns 1 after recording one event", %{org: org} do
      assert {:ok, _event} =
               Billing.record_usage_event(%{
                 organization_id: org.id,
                 event_type: "api_invocation"
               })

      assert Billing.count_usage_events_today(org.id, "api_invocation") == 1
    end

    test "count returns correct total after multiple events", %{org: org} do
      for _ <- 1..3 do
        Billing.record_usage_event(%{organization_id: org.id, event_type: "api_invocation"})
      end

      Billing.record_usage_event(%{organization_id: org.id, event_type: "llm_generation"})

      assert Billing.count_usage_events_today(org.id, "api_invocation") == 3
      assert Billing.count_usage_events_today(org.id, "llm_generation") == 1
    end

    test "count does not mix organizations", %{org: org} do
      other_user = user_fixture()
      [other_org] = Organizations.list_user_organizations(other_user)

      Billing.record_usage_event(%{organization_id: org.id, event_type: "api_invocation"})
      Billing.record_usage_event(%{organization_id: other_org.id, event_type: "api_invocation"})

      assert Billing.count_usage_events_today(org.id, "api_invocation") == 1
    end

    test "returns error changeset for invalid event_type", %{org: org} do
      assert {:error, changeset} =
               Billing.record_usage_event(%{
                 organization_id: org.id,
                 event_type: "invalid_type"
               })

      assert {:event_type, _} = hd(changeset.errors)
    end
  end

  describe "sum_monthly_usage/2" do
    setup :create_user_and_org

    test "returns 0 when no events recorded", %{org: org} do
      assert Billing.sum_monthly_usage(org.id, "api_invocation") == 0
    end

    test "includes today's live events in monthly sum", %{org: org} do
      for _ <- 1..5 do
        Billing.record_usage_event(%{organization_id: org.id, event_type: "api_invocation"})
      end

      assert Billing.sum_monthly_usage(org.id, "api_invocation") == 5
    end

    test "adds aggregated daily_usage to today's live count", %{org: org} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      # Insert a DailyUsage row for yesterday (simulating aggregation worker output)
      daily_usage_fixture(%{organization_id: org.id, date: yesterday, api_invocations: 10})

      # Record 3 more events today
      for _ <- 1..3 do
        Billing.record_usage_event(%{organization_id: org.id, event_type: "api_invocation"})
      end

      assert Billing.sum_monthly_usage(org.id, "api_invocation") == 13
    end

    test "llm_generation event type aggregates correctly", %{org: org} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      daily_usage_fixture(%{organization_id: org.id, date: yesterday, llm_generations: 7})

      Billing.record_usage_event(%{organization_id: org.id, event_type: "llm_generation"})

      assert Billing.sum_monthly_usage(org.id, "llm_generation") == 8
    end
  end

  describe "get_daily_usage/2" do
    setup :create_user_and_org

    test "returns nil when no daily usage row exists", %{org: org} do
      today = Date.utc_today()
      assert Billing.get_daily_usage(org.id, today) == nil
    end

    test "returns the daily usage row when it exists", %{org: org} do
      today = Date.utc_today()

      daily_usage_fixture(%{
        organization_id: org.id,
        date: today,
        api_invocations: 42,
        llm_generations: 7
      })

      usage = Billing.get_daily_usage(org.id, today)
      assert usage != nil
      assert usage.api_invocations == 42
      assert usage.llm_generations == 7
      assert usage.date == today
    end
  end

  describe "get_daily_usage_for_period/3" do
    setup :create_user_and_org

    test "returns empty list when no records in period", %{org: org} do
      today = Date.utc_today()
      result = Billing.get_daily_usage_for_period(org.id, today, today)
      assert result == []
    end

    test "returns records ordered by date within the period", %{org: org} do
      today = Date.utc_today()
      day1 = Date.add(today, -3)
      day2 = Date.add(today, -2)
      day3 = Date.add(today, -1)

      for {date, invocations} <- [{day2, 20}, {day1, 10}, {day3, 30}] do
        daily_usage_fixture(%{organization_id: org.id, date: date, api_invocations: invocations})
      end

      result = Billing.get_daily_usage_for_period(org.id, day1, day3)
      assert length(result) == 3
      assert Enum.map(result, & &1.date) == [day1, day2, day3]
      assert Enum.map(result, & &1.api_invocations) == [10, 20, 30]
    end

    test "excludes records outside the requested period", %{org: org} do
      today = Date.utc_today()
      in_range = Date.add(today, -2)
      out_of_range = Date.add(today, -5)

      for date <- [in_range, out_of_range] do
        daily_usage_fixture(%{organization_id: org.id, date: date, api_invocations: 5})
      end

      result = Billing.get_daily_usage_for_period(org.id, Date.add(today, -3), today)
      assert length(result) == 1
      assert hd(result).date == in_range
    end
  end

  describe "sync_subscription/1" do
    setup :create_user_and_org

    test "returns error when no subscription exists", %{org: org} do
      assert {:error, :no_subscription} = Billing.sync_subscription(org)
    end

    test "updates subscription from Stripe data", %{org: org} do
      {:ok, _sub} =
        Billing.create_or_update_subscription(%{
          organization_id: org.id,
          stripe_subscription_id: "sub_stripe_123",
          plan: "free",
          status: "active"
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      period_end = DateTime.add(now, 30 * 24 * 3600)

      Blackboex.Billing.StripeClientMock
      |> expect(:retrieve_subscription, fn "sub_stripe_123" ->
        {:ok,
         %{
           status: :active,
           cancel_at_period_end: false,
           current_period_start: DateTime.to_unix(now),
           current_period_end: DateTime.to_unix(period_end),
           items: %{data: [%{price: %{id: "price_pro_monthly"}}]}
         }}
      end)

      assert {:ok, updated_sub} = Billing.sync_subscription(org)
      assert updated_sub.plan == "pro"
      assert updated_sub.status == "active"
      assert updated_sub.cancel_at_period_end == false
    end

    test "returns error when Stripe retrieval fails", %{org: org} do
      Billing.create_or_update_subscription(%{
        organization_id: org.id,
        stripe_subscription_id: "sub_failing",
        plan: "pro",
        status: "active"
      })

      Blackboex.Billing.StripeClientMock
      |> expect(:retrieve_subscription, fn "sub_failing" ->
        {:error, :stripe_unavailable}
      end)

      assert {:error, :stripe_unavailable} = Billing.sync_subscription(org)
    end
  end
end
