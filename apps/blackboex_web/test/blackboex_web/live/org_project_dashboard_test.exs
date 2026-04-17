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
    test "redirects to the org's Default project", %{conn: conn, org: org, project: project} do
      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/orgs/#{org.slug}")
      assert path == "/orgs/#{org.slug}/projects/#{project.slug}"
    end
  end

  describe "Overview at /orgs/:org_slug/dashboard" do
    test "renders the new Overview header", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/dashboard")
      assert html =~ "Dashboard"
      assert html =~ "Total APIs"
    end

    test "shows org name in sidebar", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/dashboard")
      assert html =~ org.name
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
