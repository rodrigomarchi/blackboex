defmodule Blackboex.Apis.DashboardQueriesTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit

  alias Blackboex.Apis
  alias Blackboex.Apis.DashboardQueries
  alias Blackboex.Billing.DailyUsage
  alias Blackboex.Repo

  setup do
    {user, org} = user_and_org_fixture()

    {:ok, api} =
      Apis.create_api(%{
        name: "Test API",
        slug: "test-api-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      })

    %{org: org, api: api, user: user}
  end

  # ──────────────────────────────────────────────────────────────
  # get_org_summary/1
  # ──────────────────────────────────────────────────────────────

  describe "get_org_summary/1" do
    test "returns zeros for org with no invocations", %{org: org} do
      summary = DashboardQueries.get_org_summary(org.id)

      assert summary.total_apis == 1
      assert summary.calls_today == 0
      assert summary.errors_today == 0
      assert summary.avg_latency_today == nil
    end

    test "counts APIs correctly", %{org: org, user: user} do
      # Create additional API
      {:ok, _api2} =
        Apis.create_api(%{
          name: "API 2",
          slug: "api-2-#{System.unique_integer([:positive])}",
          template_type: "computation",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      summary = DashboardQueries.get_org_summary(org.id)
      assert summary.total_apis == 2
    end

    test "counts today's invocations and errors", %{org: org, api: api} do
      # Insert invocations for today
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 30})
      invocation_log_fixture(%{api_id: api.id, status_code: 500, duration_ms: 100})

      summary = DashboardQueries.get_org_summary(org.id)

      assert summary.calls_today == 3
      assert summary.errors_today == 1
      assert is_float(summary.avg_latency_today)
    end

    test "returns nil avg_latency when no invocations", %{org: org} do
      summary = DashboardQueries.get_org_summary(org.id)
      assert summary.avg_latency_today == nil
    end

    test "does not count invocations from other orgs", %{org: org, api: api} do
      # Create another org with invocations
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Other"})

      {:ok, other_api} =
        Apis.create_api(%{
          name: "Other API",
          slug: "other-#{System.unique_integer([:positive])}",
          template_type: "computation",
          organization_id: other_org.id,
          project_id: Blackboex.Projects.get_default_project(other_org.id).id,
          user_id: other_user.id
        })

      invocation_log_fixture(%{api_id: other_api.id, status_code: 200, duration_ms: 50})
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 30})

      summary = DashboardQueries.get_org_summary(org.id)
      assert summary.calls_today == 1
    end
  end

  # ──────────────────────────────────────────────────────────────
  # list_apis_with_stats/2
  # ──────────────────────────────────────────────────────────────

  describe "list_apis_with_stats/2" do
    test "returns API with zero stats when no invocations", %{org: org} do
      results = DashboardQueries.list_apis_with_stats(org.id)

      assert length(results) == 1
      [row] = results
      assert row.calls_24h == 0
      assert row.errors_24h == 0
      assert row.avg_latency == nil
    end

    test "returns correct stats for recent invocations", %{org: org, api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})
      invocation_log_fixture(%{api_id: api.id, status_code: 404, duration_ms: 30})

      [row] = DashboardQueries.list_apis_with_stats(org.id)

      assert row.calls_24h == 2
      assert row.errors_24h == 1
      assert is_float(row.avg_latency) or row.avg_latency == nil
    end

    test "respects limit option", %{org: org, user: user} do
      for i <- 1..5 do
        Apis.create_api(%{
          name: "API #{i}",
          slug: "api-limit-#{i}-#{System.unique_integer([:positive])}",
          template_type: "computation",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })
      end

      results = DashboardQueries.list_apis_with_stats(org.id, limit: 3)
      assert length(results) == 3
    end

    test "filters by search term", %{org: org, user: user} do
      {:ok, _} =
        Apis.create_api(%{
          name: "Calculator API",
          slug: "calc-#{System.unique_integer([:positive])}",
          template_type: "computation",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      results = DashboardQueries.list_apis_with_stats(org.id, search: "Calculator")
      assert length(results) == 1
      assert hd(results).api.name == "Calculator API"
    end

    test "search is case-insensitive", %{org: org, user: user} do
      {:ok, _} =
        Apis.create_api(%{
          name: "UPPERCASE API",
          slug: "upper-#{System.unique_integer([:positive])}",
          template_type: "computation",
          organization_id: org.id,
          project_id: Blackboex.Projects.get_default_project(org.id).id,
          user_id: user.id
        })

      results = DashboardQueries.list_apis_with_stats(org.id, search: "uppercase")
      assert length(results) == 1
    end
  end

  # ──────────────────────────────────────────────────────────────
  # search_apis/2
  # ──────────────────────────────────────────────────────────────

  describe "search_apis/2" do
    test "finds APIs by name", %{org: org} do
      results = DashboardQueries.search_apis(org.id, "Test")
      assert length(results) == 1
    end

    test "returns empty for non-matching query", %{org: org} do
      results = DashboardQueries.search_apis(org.id, "nonexistent_xyz")
      assert results == []
    end

    test "sanitizes SQL LIKE wildcards", %{org: org} do
      # % and _ are LIKE wildcards — they should be escaped
      results = DashboardQueries.search_apis(org.id, "%_\\")
      # Should not crash or return unexpected results
      assert is_list(results)
    end

    test "handles empty search string", %{org: org} do
      results = DashboardQueries.search_apis(org.id, "")
      # Empty string returns all APIs (maybe_search passes through)
      assert results != []
    end
  end

  # ──────────────────────────────────────────────────────────────
  # get_dashboard_metrics/2
  # ──────────────────────────────────────────────────────────────

  describe "get_dashboard_metrics/2" do
    test "returns empty series for org with no rollups", %{org: org} do
      metrics = DashboardQueries.get_dashboard_metrics(org.id, "24h")

      assert is_list(metrics.calls_series)
      assert is_list(metrics.errors_series)
      assert is_list(metrics.latency_avg_series)
      assert is_list(metrics.latency_p95_series)
      assert is_list(metrics.top_apis)
      assert metrics.top_apis == []
    end

    test "24h period returns 24 hourly buckets", %{org: org} do
      metrics = DashboardQueries.get_dashboard_metrics(org.id, "24h")

      assert length(metrics.calls_series) == 24
      # Labels should be "00", "01", ..., "23"
      labels = Enum.map(metrics.calls_series, & &1.label)
      assert "00" in labels
      assert "23" in labels
    end

    test "7d period returns daily buckets", %{org: org} do
      metrics = DashboardQueries.get_dashboard_metrics(org.id, "7d")

      # 7 days: today + 6 previous = 7 data points
      assert length(metrics.calls_series) == 7
    end

    test "30d period returns daily buckets", %{org: org} do
      metrics = DashboardQueries.get_dashboard_metrics(org.id, "30d")

      assert length(metrics.calls_series) == 30
    end

    test "includes rollup data in series", %{org: org, api: api} do
      today = Date.utc_today()

      insert_metric_rollup(api.id, today, 10, %{
        invocations: 100,
        errors: 5,
        avg_duration_ms: 50.0,
        p95_duration_ms: 120.0
      })

      metrics = DashboardQueries.get_dashboard_metrics(org.id, "24h")

      total_calls = Enum.map(metrics.calls_series, & &1.value) |> Enum.sum()
      assert total_calls == 100
    end

    test "top_apis returns up to 5 APIs sorted by calls", %{org: org, user: user} do
      today = Date.utc_today()

      for i <- 1..7 do
        {:ok, new_api} =
          Apis.create_api(%{
            name: "Top API #{i}",
            slug: "top-#{i}-#{System.unique_integer([:positive])}",
            template_type: "computation",
            organization_id: org.id,
            project_id: Blackboex.Projects.get_default_project(org.id).id,
            user_id: user.id
          })

        insert_metric_rollup(new_api.id, today, 0, %{
          invocations: i * 10,
          errors: 0,
          avg_duration_ms: 10.0,
          p95_duration_ms: 20.0
        })
      end

      metrics = DashboardQueries.get_dashboard_metrics(org.id, "24h")

      assert length(metrics.top_apis) == 5
      # Sorted by calls descending
      calls = Enum.map(metrics.top_apis, & &1.calls)
      assert calls == Enum.sort(calls, :desc)
    end

    test "unknown period defaults to 30d", %{org: org} do
      metrics = DashboardQueries.get_dashboard_metrics(org.id, "unknown")

      assert length(metrics.calls_series) == 30
    end
  end

  # ──────────────────────────────────────────────────────────────
  # get_llm_usage_series/2
  # ──────────────────────────────────────────────────────────────

  describe "get_llm_usage_series/2" do
    test "returns zeros for org with no usage data", %{org: org} do
      usage = DashboardQueries.get_llm_usage_series(org.id, "30d")

      assert usage.tokens_in_total == 0
      assert usage.tokens_out_total == 0
      assert usage.cost_total_cents == 0
      assert is_list(usage.generations_series)
    end

    test "aggregates daily usage correctly", %{org: org} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        date: today,
        llm_generations: 10,
        tokens_input: 1000,
        tokens_output: 500,
        llm_cost_cents: 50
      })

      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        date: yesterday,
        llm_generations: 5,
        tokens_input: 600,
        tokens_output: 300,
        llm_cost_cents: 30
      })

      usage = DashboardQueries.get_llm_usage_series(org.id, "30d")

      assert usage.tokens_in_total == 1600
      assert usage.tokens_out_total == 800
      assert usage.cost_total_cents == 80
    end

    test "7d period only includes last 7 days", %{org: org} do
      old_date = Date.add(Date.utc_today(), -10)

      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        date: old_date,
        llm_generations: 100,
        tokens_input: 9999,
        tokens_output: 9999,
        llm_cost_cents: 9999
      })

      usage = DashboardQueries.get_llm_usage_series(org.id, "7d")

      # The old data should be excluded
      assert usage.tokens_in_total == 0
    end

    test "handles nil values in daily usage", %{org: org} do
      today = Date.utc_today()

      # Insert a record with nil fields (defaults)
      %DailyUsage{}
      |> DailyUsage.changeset(%{organization_id: org.id, date: today})
      |> Repo.insert!()

      usage = DashboardQueries.get_llm_usage_series(org.id, "30d")

      assert usage.tokens_in_total == 0
      assert usage.tokens_out_total == 0
      assert usage.cost_total_cents == 0
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────

  defp insert_metric_rollup(api_id, date, hour, attrs) do
    metric_rollup_fixture(Map.merge(attrs, %{api_id: api_id, date: date, hour: hour}))
  end
end
