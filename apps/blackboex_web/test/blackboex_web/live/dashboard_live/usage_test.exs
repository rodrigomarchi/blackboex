defmodule BlackboexWeb.DashboardLive.UsageTest do
  @moduledoc """
  Tests for the dashboard Usage content in both org and project scopes.
  """
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Organizations
  alias Blackboex.Projects

  @moduletag :liveview

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Organizations.create_organization(user, %{name: "Usage Org"})

    project = Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "org scope at /orgs/:slug/settings/usage" do
    test "renders header, nav and stat cards when usage exists", %{
      conn: conn,
      org: org,
      project: project
    } do
      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        date: Date.utc_today(),
        api_invocations: 12,
        llm_generations: 3,
        tokens_input: 1000,
        tokens_output: 500,
        llm_cost_cents: 75
      })

      usage_event_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        event_type: "api_invocation"
      })

      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/settings/usage")

      assert html =~ "Usage"
      assert html =~ "API invocations"
      assert html =~ "LLM generations"
      assert html =~ "Tokens (in / out)"
      assert html =~ "LLM cost"
      assert html =~ "api_invocation"
      # Nav links resolve relative to org base_path
      assert html =~ "/orgs/#{org.slug}/settings/apis"
      assert html =~ "/orgs/#{org.slug}/settings/usage"
    end
  end

  describe "project scope at /orgs/:slug/projects/:slug/settings/usage" do
    test "renders project-scoped usage", %{
      conn: conn,
      org: org,
      project: project
    } do
      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        date: Date.utc_today(),
        api_invocations: 5
      })

      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/usage")

      assert html =~ "Usage"
      assert html =~ "/orgs/#{org.slug}/projects/#{project.slug}/settings/usage"
    end

    test "excludes usage from other projects in same org", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      other_project = project_fixture(%{user: user, org: org, name: "Other Project"})

      # Other project has usage; current project has none
      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: other_project.id,
        date: Date.utc_today(),
        api_invocations: 99,
        llm_generations: 99,
        llm_cost_cents: 99_999
      })

      usage_event_fixture(%{
        organization_id: org.id,
        project_id: other_project.id,
        event_type: "llm_generation"
      })

      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/usage")

      assert html =~ "API invocations"
      refute html =~ "llm_generation"
    end
  end

  describe "period filter" do
    test "period link patches the URL and updates assigns", %{
      conn: conn,
      org: org,
      project: project
    } do
      daily_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        date: Date.utc_today(),
        api_invocations: 1
      })

      {:ok, lv, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/usage")

      html =
        render_patch(
          lv,
          ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/usage?period=7d"
        )

      assert html =~ "period=7d"
      assert html =~ "Usage"
    end

    test "invalid period falls back to default", %{conn: conn, org: org, project: project} do
      {:ok, _lv, html} =
        live(
          conn,
          ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/usage?period=bogus"
        )

      assert html =~ "Usage"
    end
  end

  describe "empty state" do
    test "renders stat cards with zero values when no usage exists", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/usage")

      assert html =~ "API invocations"
      assert html =~ "LLM generations"
      assert html =~ "LLM cost"
    end
  end
end
