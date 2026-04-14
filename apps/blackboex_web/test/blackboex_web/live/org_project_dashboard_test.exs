defmodule BlackboexWeb.OrgProjectDashboardTest do
  @moduledoc """
  Tests for OrgDashboardLive and ProjectDashboardLive stats rendering.
  """

  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Billing
  alias Blackboex.Billing.UsageAggregationWorker

  @moduletag :liveview

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Dashboard Test Org"})

    project = Blackboex.Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "OrgDashboardLive at /orgs/:org_slug" do
    test "mounts and renders org dashboard title", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}")
      assert html =~ "Org Dashboard"
    end

    test "shows stat cards", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}")
      assert html =~ "Total APIs"
      assert html =~ "Total Projects"
      assert html =~ "API Invocations"
      assert html =~ "LLM Calls"
    end

    test "shows org name", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}")
      assert html =~ org.name
    end

    test "shows zero counts when no usage data", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}")
      assert html =~ "0"
    end

    test "shows aggregated usage after aggregation runs", %{
      conn: conn,
      org: org,
      project: project
    } do
      today = Date.utc_today()

      for _ <- 1..3 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            project_id: project.id,
            event_type: "api_invocation"
          })
      end

      UsageAggregationWorker.aggregate_for_date(today)

      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}")
      assert html =~ "3"
    end
  end

  describe "ProjectDashboardLive at /orgs/:org_slug/projects/:project_slug" do
    test "mounts and renders project dashboard title", %{conn: conn, org: org, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}")
      assert html =~ "Project overview"
    end

    test "shows stat cards", %{conn: conn, org: org, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}")
      assert html =~ "Total APIs"
      assert html =~ "API Invocations"
      assert html =~ "LLM Calls"
    end

    test "shows project name", %{conn: conn, org: org, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}")
      assert html =~ project.name
    end

    test "shows zero counts when no usage data", %{conn: conn, org: org, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}")
      assert html =~ "0"
    end

    test "shows aggregated usage after aggregation runs", %{
      conn: conn,
      org: org,
      project: project
    } do
      today = Date.utc_today()

      for _ <- 1..2 do
        {:ok, _} =
          Billing.record_usage_event(%{
            organization_id: org.id,
            project_id: project.id,
            event_type: "api_invocation"
          })
      end

      UsageAggregationWorker.aggregate_for_date(today)

      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}")
      assert html =~ "2"
    end
  end
end
