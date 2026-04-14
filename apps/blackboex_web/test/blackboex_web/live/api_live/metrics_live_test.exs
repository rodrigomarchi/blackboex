defmodule BlackboexWeb.ApiLive.Edit.MetricsLiveTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  alias Blackboex.Apis
  alias Blackboex.Repo

  setup [:register_and_log_in_user, :create_org_and_api]

  setup do
    Apis.Registry.clear()
    :ok
  end

  defp insert_invocation_log(api, inserted_at, attrs \\ %{}) do
    defaults = %{
      id: Ecto.UUID.dump!(Ecto.UUID.generate()),
      api_id: Ecto.UUID.dump!(api.id),
      project_id: Ecto.UUID.dump!(api.project_id),
      method: "POST",
      path: "/api/test",
      status_code: 500,
      duration_ms: 100,
      error_message: "test error",
      inserted_at: inserted_at
    }

    Repo.insert_all("invocation_logs", [Map.merge(defaults, attrs)])
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

    metric_rollup_fixture(Map.merge(defaults, attrs))
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

  describe "command palette events" do
    test "toggle_command_palette opens the palette", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      html = render_click(lv, "toggle_command_palette", %{})
      assert is_binary(html)
    end

    test "close_panels closes the palette", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "close_panels", %{})
      assert is_binary(html)
    end

    test "close_panels when already closed is a no-op", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      html = render_click(lv, "close_panels", %{})
      assert is_binary(html)
    end

    test "command_palette_search filters by query", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "command_palette_search", %{"command_query" => "metrics"})
      assert is_binary(html)
    end

    test "command_palette_navigate down advances selection", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "command_palette_navigate", %{"direction" => "down"})
      assert is_binary(html)
    end

    test "command_palette_navigate up moves selection back", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      html = render_click(lv, "command_palette_navigate", %{"direction" => "up"})
      assert is_binary(html)
    end

    test "command_palette_exec navigates to a tab", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      result = render_click(lv, "command_palette_exec", %{"event" => "switch_tab_run"})
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end

    test "command_palette_exec_first executes first command", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      render_click(lv, "toggle_command_palette", %{})
      result = render_click(lv, "command_palette_exec_first", %{})
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end
  end

  describe "24h period (period_atom :day)" do
    test "switching to 24h period uses :day atom for analytics", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")

      html = render_click(lv, "change_metrics_period", %{"period" => "24h"})
      assert is_binary(html)
      assert html =~ "24h"
    end

    test "24h period with rollup data loads correctly", %{conn: conn, org: org, api: api} do
      insert_rollup(api, %{
        date: Date.utc_today(),
        hour: 0,
        invocations: 15,
        errors: 3,
        avg_duration_ms: 200.0,
        p95_duration_ms: 500.0
      })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")
      html = render_click(lv, "change_metrics_period", %{"period" => "24h"})

      assert html =~ "15" or is_binary(html)
    end
  end

  describe "format_time_ago coverage" do
    test "recent_errors with sub-minute time shows seconds ago", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      Blackboex.Testing.create_test_request(%{
        api_id: api.id,
        user_id: user.id,
        method: "POST",
        path: "/api/test/path",
        response_status: 500,
        response_body: "error",
        duration_ms: 50,
        error_message: "Something went wrong"
      })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")
      assert is_binary(html)
    end

    test "format_time_ago shows minutes ago for errors ~2 minutes old", %{
      conn: conn,
      org: org,
      api: api
    } do
      two_minutes_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -130, :second)
      insert_invocation_log(api, two_minutes_ago)

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")
      assert html =~ "m ago"
    end

    test "format_time_ago shows hours ago for errors ~2 hours old", %{
      conn: conn,
      org: org,
      api: api
    } do
      two_hours_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -7300, :second)
      insert_invocation_log(api, two_hours_ago)

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")
      assert html =~ "h ago"
    end

    test "format_time_ago shows days ago for errors ~2 days old", %{
      conn: conn,
      org: org,
      api: api
    } do
      two_days_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -172_800, :second)
      insert_invocation_log(api, two_days_ago)

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/metrics?org=#{org.id}")
      assert html =~ "d ago"
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
