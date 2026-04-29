defmodule Blackboex.Apis.DashboardQueriesTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit

  alias Blackboex.Apis
  alias Blackboex.Apis.DashboardQueries
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
  # overview_summary/1
  # ──────────────────────────────────────────────────────────────

  describe "overview_summary/1 with {:org, id}" do
    test "aggregates counts across all projects in org", %{org: org, api: api, user: user} do
      # Default project already has one API
      other_project =
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org, name: "Side"})

      api_fixture(%{user: user, org: org, project: other_project, name: "Side API"})

      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})

      summary = DashboardQueries.overview_summary({:org, org.id})

      assert summary.total_apis == 2
      assert summary.invocations_24h == 1
      assert summary.errors_24h == 0
      assert is_list(summary.recent_activity)
    end

    test "counts errors separately", %{org: org, api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})
      invocation_log_fixture(%{api_id: api.id, status_code: 500, duration_ms: 10})

      summary = DashboardQueries.overview_summary({:org, org.id})

      assert summary.invocations_24h == 2
      assert summary.errors_24h == 1
    end

    test "recent_activity includes the API name", %{org: org, api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})

      summary = DashboardQueries.overview_summary({:org, org.id})

      assert [entry | _] = summary.recent_activity
      assert entry.api_name == api.name
      assert entry.status_code == 200
    end

    test "returns zero counts for empty org" do
      other_user = user_fixture()

      {:ok, %{organization: empty_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Empty"})

      # The create_organization already creates a Default project + API?
      # Default project is created but APIs aren't auto-created.
      summary = DashboardQueries.overview_summary({:org, empty_org.id})

      assert summary.total_apis == 0
      assert summary.total_flows == 0
      assert summary.total_api_keys == 0
      assert summary.invocations_24h == 0
      assert summary.errors_24h == 0
      assert summary.recent_activity == []
    end
  end

  describe "overview_summary/1 with {:project, id}" do
    test "excludes rows from other projects in same org", %{org: org, api: api, user: user} do
      other_project =
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org, name: "Side"})

      other_api = api_fixture(%{user: user, org: org, project: other_project, name: "Side"})

      # Activity on both projects
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})
      invocation_log_fixture(%{api_id: other_api.id, status_code: 200, duration_ms: 50})
      invocation_log_fixture(%{api_id: other_api.id, status_code: 500, duration_ms: 10})

      default_project = Blackboex.Projects.get_default_project(org.id)

      summary = DashboardQueries.overview_summary({:project, default_project.id})

      # Only the default project's API and invocation should count
      assert summary.total_apis == 1
      assert summary.invocations_24h == 1
      assert summary.errors_24h == 0

      assert [entry] = summary.recent_activity
      assert entry.api_name == api.name
    end
  end

  # ──────────────────────────────────────────────────────────────
  # api_metrics/2
  # ──────────────────────────────────────────────────────────────

  describe "api_metrics/2 with {:org, id}" do
    test "returns zeros for org with no invocations", %{org: org} do
      metrics = DashboardQueries.api_metrics({:org, org.id}, "24h")

      assert metrics.invocations_total == 0
      assert metrics.invocations_success == 0
      assert metrics.invocations_error == 0
      assert metrics.error_rate == 0.0
      assert metrics.avg_latency_ms == nil
      assert metrics.p95_latency_ms == nil
      assert metrics.top_apis == []
    end

    test "aggregates totals, success, errors and rates", %{org: org, api: api} do
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 80})
      invocation_log_fixture(%{api_id: api.id, status_code: 500, duration_ms: 120})

      metrics = DashboardQueries.api_metrics({:org, org.id}, "24h")

      assert metrics.invocations_total == 3
      assert metrics.invocations_success == 2
      assert metrics.invocations_error == 1
      assert metrics.error_rate == Float.round(1 / 3 * 100, 1)
      assert is_float(metrics.avg_latency_ms)
      assert is_float(metrics.p95_latency_ms)
    end

    test "excludes invocations from other orgs", %{org: org, api: api} do
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Other Org"})

      {:ok, other_api} =
        Apis.create_api(%{
          name: "Other Org API",
          slug: "other-org-#{System.unique_integer([:positive])}",
          template_type: "computation",
          organization_id: other_org.id,
          project_id: Blackboex.Projects.get_default_project(other_org.id).id,
          user_id: other_user.id
        })

      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})
      invocation_log_fixture(%{api_id: other_api.id, status_code: 200, duration_ms: 80})

      metrics = DashboardQueries.api_metrics({:org, org.id}, "24h")
      assert metrics.invocations_total == 1
    end

    test "respects period window — 24h excludes older logs", %{org: org, api: api} do
      old_inserted = DateTime.add(DateTime.utc_now(), -2 * 86_400)
      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})
      old_log = invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})

      Repo.update_all(
        from(l in Blackboex.Apis.InvocationLog, where: l.id == ^old_log.id),
        set: [inserted_at: old_inserted]
      )

      metrics = DashboardQueries.api_metrics({:org, org.id}, "24h")
      assert metrics.invocations_total == 1
    end

    test "top_apis sorted by invocations desc, capped at 10", %{org: org, user: user} do
      apis =
        for i <- 1..12 do
          {:ok, api} =
            Apis.create_api(%{
              name: "Top API #{i}",
              slug: "top-api-#{i}-#{System.unique_integer([:positive])}",
              template_type: "computation",
              organization_id: org.id,
              project_id: Blackboex.Projects.get_default_project(org.id).id,
              user_id: user.id
            })

          for _ <- 1..i do
            invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 10})
          end

          api
        end

      metrics = DashboardQueries.api_metrics({:org, org.id}, "24h")

      assert length(metrics.top_apis) == 10
      counts = Enum.map(metrics.top_apis, & &1.invocations)
      assert counts == Enum.sort(counts, :desc)

      # Highest count was 12; lowest in top-10 should be 3
      # (we drop the two smallest of 13 APIs incl. the seeded one)
      assert hd(metrics.top_apis).invocations == 12
      assert hd(metrics.top_apis).api_name == "Top API 12"
      assert hd(metrics.top_apis).api_id == hd(Enum.reverse(apis)).id
      assert is_float(hd(metrics.top_apis).error_rate) or hd(metrics.top_apis).error_rate == 0.0
    end
  end

  describe "api_metrics/2 with {:project, id}" do
    test "filters by project_id and excludes other projects", %{org: org, api: api, user: user} do
      other_project =
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org, name: "Side"})

      other_api = api_fixture(%{user: user, org: org, project: other_project, name: "Side API"})

      invocation_log_fixture(%{api_id: api.id, status_code: 200, duration_ms: 50})
      invocation_log_fixture(%{api_id: other_api.id, status_code: 200, duration_ms: 80})
      invocation_log_fixture(%{api_id: other_api.id, status_code: 500, duration_ms: 10})

      default_project = Blackboex.Projects.get_default_project(org.id)

      metrics = DashboardQueries.api_metrics({:project, default_project.id}, "24h")

      assert metrics.invocations_total == 1
      assert metrics.invocations_success == 1
      assert metrics.invocations_error == 0
      assert [%{api_name: name, invocations: 1}] = metrics.top_apis
      assert name == api.name
    end

    test "returns zeros for empty project" do
      other_user = user_fixture()

      {:ok, %{organization: empty_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Empty"})

      project = Blackboex.Projects.get_default_project(empty_org.id)

      metrics = DashboardQueries.api_metrics({:project, project.id}, "7d")

      assert metrics.invocations_total == 0
      assert metrics.top_apis == []
    end
  end

  # ──────────────────────────────────────────────────────────────
  # flow_metrics/2
  # ──────────────────────────────────────────────────────────────

  describe "flow_metrics/2 with {:org, id}" do
    test "returns zeros for org with no executions", %{org: org} do
      metrics = DashboardQueries.flow_metrics({:org, org.id}, "24h")

      assert metrics.total_flows == 0
      assert metrics.executions_total == 0
      assert metrics.executions_success == 0
      assert metrics.executions_error == 0
      assert metrics.executions_pending == 0
      assert metrics.error_rate == 0.0
      assert metrics.avg_duration_ms == nil
      assert metrics.top_flows == []
    end

    test "aggregates executions across all projects in org", %{org: org, user: user} do
      flow_a = flow_fixture(%{user: user, org: org, name: "Flow A"})

      other_project =
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org, name: "Other"})

      flow_b = flow_fixture(%{user: user, org: org, project: other_project, name: "Flow B"})

      complete_flow_execution!(flow_a, 100)
      complete_flow_execution!(flow_b, 200)
      fail_flow_execution!(flow_b)

      metrics = DashboardQueries.flow_metrics({:org, org.id}, "24h")

      assert metrics.total_flows == 2
      assert metrics.executions_total == 3
      assert metrics.executions_success == 2
      assert metrics.executions_error == 1
      assert metrics.error_rate == Float.round(1 / 3 * 100, 1)
      assert is_float(metrics.avg_duration_ms)
    end

    test "top_flows is sorted by execution count desc and limited to 10",
         %{org: org, user: user} do
      for i <- 1..12 do
        flow = flow_fixture(%{user: user, org: org, name: "Flow #{i}"})

        for _ <- 1..i do
          complete_flow_execution!(flow, 50)
        end
      end

      metrics = DashboardQueries.flow_metrics({:org, org.id}, "24h")

      assert length(metrics.top_flows) == 10
      execs = Enum.map(metrics.top_flows, & &1.executions)
      assert execs == Enum.sort(execs, :desc)

      [first | _] = metrics.top_flows
      assert is_binary(first.flow_id)
      assert is_float(first.error_rate)
    end

    test "counts pending/running/halted as pending bucket", %{org: org, user: user} do
      flow = flow_fixture(%{user: user, org: org, name: "Pending Flow"})
      _exec = flow_execution_fixture(%{flow: flow})

      metrics = DashboardQueries.flow_metrics({:org, org.id}, "24h")

      assert metrics.executions_pending == 1
      assert metrics.executions_total == 1
      assert metrics.executions_success == 0
      assert metrics.executions_error == 0
    end

    test "excludes executions outside the period window", %{org: org, user: user} do
      flow = flow_fixture(%{user: user, org: org, name: "Old Flow"})
      execution = complete_flow_execution!(flow, 10)

      old_dt = DateTime.add(DateTime.utc_now(), -8 * 86_400) |> DateTime.truncate(:second)

      from(e in Blackboex.FlowExecutions.FlowExecution, where: e.id == ^execution.id)
      |> Repo.update_all(set: [inserted_at: old_dt])

      metrics = DashboardQueries.flow_metrics({:org, org.id}, "24h")

      assert metrics.executions_total == 0
      # total_flows ignores the period and counts the flow
      assert metrics.total_flows == 1
    end
  end

  describe "flow_metrics/2 with {:project, id}" do
    test "excludes executions from other projects in same org", %{org: org, user: user} do
      other_project =
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org, name: "Side"})

      default_flow = flow_fixture(%{user: user, org: org, name: "Default Flow"})
      side_flow = flow_fixture(%{user: user, org: org, project: other_project, name: "Side"})

      complete_flow_execution!(default_flow, 30)
      complete_flow_execution!(side_flow, 40)
      fail_flow_execution!(side_flow)

      default_project = Blackboex.Projects.get_default_project(org.id)

      metrics = DashboardQueries.flow_metrics({:project, default_project.id}, "24h")

      assert metrics.total_flows == 1
      assert metrics.executions_total == 1
      assert metrics.executions_success == 1
      assert metrics.executions_error == 0

      assert [%{flow_name: "Default Flow"}] = metrics.top_flows
    end
  end

  # ──────────────────────────────────────────────────────────────
  # llm_metrics/2 (scope-aware) — M4
  # ──────────────────────────────────────────────────────────────

  describe "llm_metrics/2 with {:org, id}" do
    test "returns zeros for org with no usage", %{org: org} do
      metrics = DashboardQueries.llm_metrics({:org, org.id}, "30d")

      assert metrics.total_generations == 0
      assert metrics.total_tokens_input == 0
      assert metrics.total_tokens_output == 0
      assert metrics.estimated_cost_cents == 0
      assert metrics.by_model == []
    end

    test "aggregates across projects in the org", %{org: org, user: user} do
      default = Blackboex.Projects.get_default_project(org.id)

      other_project =
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org, name: "Side"})

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: default.id,
        model: "gpt-4o-mini",
        input_tokens: 100,
        output_tokens: 50,
        cost_cents: 5
      })

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: other_project.id,
        model: "gpt-4o-mini",
        input_tokens: 200,
        output_tokens: 100,
        cost_cents: 10
      })

      metrics = DashboardQueries.llm_metrics({:org, org.id}, "30d")

      assert metrics.total_generations == 2
      assert metrics.total_tokens_input == 300
      assert metrics.total_tokens_output == 150
      assert metrics.estimated_cost_cents == 15
    end

    test "by_model groups by model and orders by tokens desc", %{org: org} do
      project = Blackboex.Projects.get_default_project(org.id)

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        model: "small",
        input_tokens: 10,
        output_tokens: 5,
        cost_cents: 1
      })

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        model: "big",
        input_tokens: 1000,
        output_tokens: 500,
        cost_cents: 100
      })

      metrics = DashboardQueries.llm_metrics({:org, org.id}, "30d")

      assert [%{model: "big", tokens: 1500} | _] = metrics.by_model
      assert Enum.map(metrics.by_model, & &1.model) == ["big", "small"]
    end

    test "does not count usage from other orgs", %{org: org} do
      project = Blackboex.Projects.get_default_project(org.id)
      other_user = user_fixture()

      {:ok, %{organization: other_org}} =
        Blackboex.Organizations.create_organization(other_user, %{name: "Other"})

      other_project = Blackboex.Projects.get_default_project(other_org.id)

      llm_usage_fixture(%{
        organization_id: other_org.id,
        project_id: other_project.id,
        model: "gpt-4o-mini",
        input_tokens: 999,
        output_tokens: 999,
        cost_cents: 999
      })

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        model: "gpt-4o-mini",
        input_tokens: 10,
        output_tokens: 5,
        cost_cents: 1
      })

      metrics = DashboardQueries.llm_metrics({:org, org.id}, "30d")

      assert metrics.total_generations == 1
      assert metrics.total_tokens_input == 10
    end
  end

  describe "llm_metrics/2 with {:project, id}" do
    test "excludes rows from other projects in the same org", %{org: org, user: user} do
      default = Blackboex.Projects.get_default_project(org.id)

      other_project =
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org, name: "Side"})

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: default.id,
        model: "in-scope",
        input_tokens: 10,
        output_tokens: 5,
        cost_cents: 1
      })

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: other_project.id,
        model: "out-of-scope",
        input_tokens: 999,
        output_tokens: 999,
        cost_cents: 999
      })

      metrics = DashboardQueries.llm_metrics({:project, default.id}, "30d")

      assert metrics.total_generations == 1
      assert metrics.total_tokens_input == 10
      assert [%{model: "in-scope"}] = metrics.by_model
    end
  end

  # ──────────────────────────────────────────────────────────────
  # llm_usage_series/2 (scope-aware) — M4
  # ──────────────────────────────────────────────────────────────

  describe "llm_usage_series/2" do
    test "returns gap-filled series of expected length", %{org: org} do
      series = DashboardQueries.llm_usage_series({:org, org.id}, "7d")

      # 7 days back + today = 8 entries
      assert length(series) == 8

      Enum.each(series, fn row ->
        assert %Date{} = row.date
        assert row.tokens == 0
        assert row.cost_cents == 0
        assert row.generations == 0
      end)
    end

    test "aggregates same-day usage into one bucket", %{org: org} do
      project = Blackboex.Projects.get_default_project(org.id)

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        input_tokens: 100,
        output_tokens: 50,
        cost_cents: 3
      })

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        input_tokens: 200,
        output_tokens: 100,
        cost_cents: 7
      })

      series = DashboardQueries.llm_usage_series({:org, org.id}, "7d")

      totals =
        Enum.reduce(series, %{tokens: 0, cost: 0, gens: 0}, fn row, acc ->
          %{
            tokens: acc.tokens + row.tokens,
            cost: acc.cost + row.cost_cents,
            gens: acc.gens + row.generations
          }
        end)

      assert totals.tokens == 450
      assert totals.cost == 10
      assert totals.gens == 2
    end

    test "project scope isolates data", %{org: org, user: user} do
      default = Blackboex.Projects.get_default_project(org.id)

      other_project =
        Blackboex.ProjectsFixtures.project_fixture(%{user: user, org: org, name: "Side"})

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: other_project.id,
        input_tokens: 999,
        output_tokens: 999,
        cost_cents: 999
      })

      series = DashboardQueries.llm_usage_series({:project, default.id}, "7d")
      total_tokens = series |> Enum.map(& &1.tokens) |> Enum.sum()
      assert total_tokens == 0
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────

  defp insert_metric_rollup(api_id, date, hour, attrs) do
    metric_rollup_fixture(Map.merge(attrs, %{api_id: api_id, date: date, hour: hour}))
  end

  defp complete_flow_execution!(flow, duration_ms) do
    execution = flow_execution_fixture(%{flow: flow})

    execution
    |> Ecto.Changeset.change(%{
      status: "completed",
      duration_ms: duration_ms,
      finished_at: DateTime.utc_now()
    })
    |> Repo.update!()
  end

  defp fail_flow_execution!(flow) do
    execution = flow_execution_fixture(%{flow: flow})

    execution
    |> Ecto.Changeset.change(%{
      status: "failed",
      error: "boom",
      finished_at: DateTime.utc_now()
    })
    |> Repo.update!()
  end
end
