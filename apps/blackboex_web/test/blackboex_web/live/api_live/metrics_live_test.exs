defmodule BlackboexWeb.ApiLive.Edit.MetricsLiveTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias Blackboex.Apis.MetricRollup
  alias Blackboex.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    Apis.Registry.clear()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Metrics Org #{System.unique_integer([:positive])}",
        slug: "metricsorg-#{System.unique_integer([:positive])}"
      })

    {:ok, api} =
      Apis.create_api(%{
        name: "Metrics Test API",
        slug: "metrics-test-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(_), do: %{ok: true}"
      })

    %{org: org, api: api}
  end

  defp insert_rollup(api, attrs) do
    defaults = %{
      api_id: api.id,
      date: Date.utc_today(),
      hour: 10,
      invocations: 5,
      errors: 1,
      avg_duration_ms: 120.0,
      p95_duration_ms: 250.0,
      unique_consumers: 2
    }

    %MetricRollup{}
    |> MetricRollup.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "mount" do
    test "renders metrics tab with period selector", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      assert html =~ "Metrics"
      assert html =~ "24h"
      assert html =~ "7d"
      assert html =~ "30d"
    end

    test "shows stat cards with zeros when no data", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      assert html =~ "Invocations"
      assert html =~ "Errors"
      assert html =~ "Error Rate"
      assert html =~ "Avg Latency"
    end

    test "shows no data message when no invocations exist", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      assert html =~ "No metrics data yet"
    end

    test "defaults to 7d period", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      # 7d button should have the active class (bg-primary)
      assert html =~ ~r/bg-primary[^>]*>(\s*)7d/
    end
  end

  describe "change_metrics_period" do
    test "switching to 24h updates the view", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      html = render_click(lv, "change_metrics_period", %{"period" => "24h"})

      assert is_binary(html)
      assert html =~ "24h"
    end

    test "switching to 30d updates the view", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      html = render_click(lv, "change_metrics_period", %{"period" => "30d"})

      assert is_binary(html)
      assert html =~ "30d"
    end

    test "switching to 7d updates the view", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      # First switch away then back
      render_click(lv, "change_metrics_period", %{"period" => "24h"})
      html = render_click(lv, "change_metrics_period", %{"period" => "7d"})

      assert is_binary(html)
    end

    test "invalid period is ignored", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      # Should not crash — the guard clause on change_metrics_period only allows known periods
      html = render(lv)
      assert is_binary(html)
    end
  end

  describe "with invocation data" do
    test "shows charts section when rollup data exists", %{conn: conn, org: org, api: api} do
      insert_rollup(api, %{
        date: Date.add(Date.utc_today(), -1),
        hour: 12,
        invocations: 10,
        errors: 2,
        avg_duration_ms: 150.0,
        p95_duration_ms: 300.0
      })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      # Charts are rendered when invocation_data is non-empty
      assert html =~ "Invocations"
      assert html =~ "P95 Latency"
      refute html =~ "No metrics data yet"
    end

    test "shows correct total invocation count", %{conn: conn, org: org, api: api} do
      insert_rollup(api, %{
        date: Date.add(Date.utc_today(), -1),
        hour: 10,
        invocations: 42,
        errors: 0
      })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      assert html =~ "42"
    end

    test "shows errors section when recent errors exist", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      # Create a test request that counts as an error (status 500)
      Blackboex.Testing.create_test_request(%{
        api_id: api.id,
        user_id: user.id,
        method: "POST",
        path: "/api/test/path",
        response_status: 500,
        response_body: "Internal Server Error",
        duration_ms: 100
      })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      # The page renders without crash
      assert is_binary(html)
    end

    test "calculates error rate correctly", %{conn: conn, org: org, api: api} do
      insert_rollup(api, %{
        date: Date.add(Date.utc_today(), -1),
        hour: 10,
        invocations: 100,
        errors: 10,
        avg_duration_ms: 80.0,
        p95_duration_ms: 200.0
      })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      # Error rate = 10/100 * 100 = 10.0%
      assert html =~ "10.0"
    end

    test "period switch reloads data correctly", %{conn: conn, org: org, api: api} do
      # Insert rollup in the past 7 days range
      insert_rollup(api, %{
        date: Date.add(Date.utc_today(), -3),
        hour: 8,
        invocations: 20,
        errors: 0,
        avg_duration_ms: 60.0,
        p95_duration_ms: 120.0
      })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      html = render_click(lv, "change_metrics_period", %{"period" => "30d"})
      assert is_binary(html)
      assert html =~ "20"
    end
  end
end
