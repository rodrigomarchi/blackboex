defmodule Blackboex.Billing.UsageAggregationWorkerTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Billing
  alias Blackboex.Billing.UsageAggregationWorker
  alias Blackboex.Organizations

  import Blackboex.AccountsFixtures

  @moduletag :unit

  defp create_org(_context) do
    user = user_fixture()
    [org] = Organizations.list_user_organizations(user)
    %{org: org}
  end

  describe "aggregate_for_date/1" do
    setup [:create_org]

    test "aggregates usage events into daily usage", %{org: org} do
      today = Date.utc_today()

      # Create some usage events for today
      for _ <- 1..5 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "api_invocation"
          })
      end

      for _ <- 1..3 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "llm_generation"
          })
      end

      assert :ok = UsageAggregationWorker.aggregate_for_date(today)

      daily = Billing.get_daily_usage(org.id, today)
      assert daily.api_invocations == 5
      assert daily.llm_generations == 3
    end

    test "is idempotent — re-running replaces values", %{org: org} do
      today = Date.utc_today()

      for _ <- 1..3 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            event_type: "api_invocation"
          })
      end

      assert :ok = UsageAggregationWorker.aggregate_for_date(today)
      daily1 = Billing.get_daily_usage(org.id, today)
      assert daily1.api_invocations == 3

      # Run again — should produce same result (not double)
      assert :ok = UsageAggregationWorker.aggregate_for_date(today)
      daily2 = Billing.get_daily_usage(org.id, today)
      assert daily2.api_invocations == 3
    end

    test "handles no events gracefully", %{org: _org} do
      yesterday = Date.add(Date.utc_today(), -1)
      assert :ok = UsageAggregationWorker.aggregate_for_date(yesterday)
    end
  end
end
