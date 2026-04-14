defmodule Blackboex.Billing.UsageAggregationWorkerTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Billing
  alias Blackboex.Billing.{DailyUsage, UsageAggregationWorker}
  alias Blackboex.Repo

  import Ecto.Query, warn: false

  @moduletag :unit

  describe "aggregate_for_date/1" do
    setup :create_user_and_org

    test "aggregates usage events into daily usage", %{org: org} do
      today = Date.utc_today()
      project_id = Blackboex.Projects.get_default_project(org.id).id

      for _ <- 1..5 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            project_id: project_id,
            event_type: "api_invocation"
          })
      end

      for _ <- 1..3 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            project_id: project_id,
            event_type: "llm_generation"
          })
      end

      assert :ok = UsageAggregationWorker.aggregate_for_date(today)

      daily = Billing.get_daily_usage(org.id, today)
      assert daily.api_invocations == 5
      assert daily.llm_generations == 3
    end

    test "creates both project-level and org-level records", %{org: org} do
      today = Date.utc_today()
      project_id = Blackboex.Projects.get_default_project(org.id).id

      for _ <- 1..4 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            project_id: project_id,
            event_type: "api_invocation"
          })
      end

      assert :ok = UsageAggregationWorker.aggregate_for_date(today)

      # Project-level record (project_id set)
      project_record =
        Repo.one(
          from d in DailyUsage,
            where:
              d.organization_id == ^org.id and d.project_id == ^project_id and
                d.date == ^today
        )

      assert project_record != nil
      assert project_record.api_invocations == 4

      # Org-level record (project_id: nil)
      org_record =
        Repo.one(
          from d in DailyUsage,
            where: d.organization_id == ^org.id and is_nil(d.project_id) and d.date == ^today
        )

      assert org_record != nil
      assert org_record.api_invocations == 4
    end

    test "is idempotent — re-running replaces values", %{org: org} do
      today = Date.utc_today()
      project_id = Blackboex.Projects.get_default_project(org.id).id

      for _ <- 1..3 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            project_id: project_id,
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

  describe "get_org_usage_summary/2" do
    setup :create_user_and_org

    test "returns summed totals from org-level records (project_id nil)", %{org: org} do
      yesterday = Date.add(Date.utc_today(), -1)

      # Org-level rollup record (project_id: nil)
      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: nil,
        date: yesterday,
        api_invocations: 10,
        llm_generations: 5
      })

      summary = Billing.get_org_usage_summary(org.id)

      assert summary.api_invocations == 10
      assert summary.llm_generations == 5
    end

    test "does not include project-level records in org summary", %{org: org} do
      yesterday = Date.add(Date.utc_today(), -1)
      project_id = Blackboex.Projects.get_default_project(org.id).id

      # Project-level record — should NOT be included
      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: project_id,
        date: yesterday,
        api_invocations: 99
      })

      summary = Billing.get_org_usage_summary(org.id)
      assert summary.api_invocations == 0
    end
  end

  describe "get_project_usage_summary/2" do
    setup :create_user_and_org

    test "returns summed totals for the given project", %{org: org} do
      yesterday = Date.add(Date.utc_today(), -1)
      project_id = Blackboex.Projects.get_default_project(org.id).id

      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: project_id,
        date: yesterday,
        api_invocations: 7,
        llm_generations: 2
      })

      summary = Billing.get_project_usage_summary(project_id)

      assert summary.api_invocations == 7
      assert summary.llm_generations == 2
    end

    test "does not include other project records", %{org: org} do
      yesterday = Date.add(Date.utc_today(), -1)
      project_id = Blackboex.Projects.get_default_project(org.id).id

      # Org-level record (nil) — should NOT count
      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: nil,
        date: yesterday,
        api_invocations: 50
      })

      summary = Billing.get_project_usage_summary(project_id)
      assert summary.api_invocations == 0
    end
  end
end
