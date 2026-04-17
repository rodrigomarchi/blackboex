defmodule BlackboexWeb.DashboardLive.FlowsTest do
  @moduledoc """
  Tests for the dashboard Flows LiveView in both org and project scopes.
  """
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Organizations
  alias Blackboex.Projects
  alias Blackboex.Repo

  @moduletag :liveview

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Organizations.create_organization(user, %{name: "Flows Org"})

    project = Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "org scope at /orgs/:slug/dashboard/flows" do
    test "renders header, nav and stat cards when executions exist", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      flow = flow_fixture(%{user: user, org: org, project: project, name: "Org Scope Flow"})
      complete_execution!(flow)

      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/dashboard/flows")

      assert html =~ "Flows"
      assert html =~ "Organization flow executions"
      assert html =~ "Total Flows"
      assert html =~ "Executions"
      assert html =~ "Success Rate"
      assert html =~ "Avg Duration"
      assert html =~ "Org Scope Flow"
      # Nav links resolve relative to org base_path
      assert html =~ "/orgs/#{org.slug}/dashboard/apis"
      assert html =~ "/orgs/#{org.slug}/dashboard/flows"
    end
  end

  describe "project scope at /orgs/:slug/projects/:slug/dashboard/flows" do
    test "renders project-scoped flow stats", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      flow =
        flow_fixture(%{user: user, org: org, project: project, name: "Project Scope Flow"})

      complete_execution!(flow)

      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/dashboard/flows")

      assert html =~ "Flows"
      assert html =~ "Project flow executions"
      assert html =~ "Project Scope Flow"
      assert html =~ "/orgs/#{org.slug}/projects/#{project.slug}/dashboard/flows"
    end

    test "excludes executions from other projects in same org", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      other_project = project_fixture(%{user: user, org: org, name: "Other Project"})

      other_flow =
        flow_fixture(%{user: user, org: org, project: other_project, name: "Other Project Flow"})

      complete_execution!(other_flow)

      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/dashboard/flows")

      refute html =~ "Other Project Flow"
      assert html =~ "Total Flows"
    end
  end

  describe "period filter" do
    test "set_period event navigates with the new period", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      flow = flow_fixture(%{user: user, org: org, project: project, name: "Period Flow"})
      complete_execution!(flow)

      {:ok, lv, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/dashboard/flows")

      lv
      |> element("button", "7 days")
      |> render_click()

      assert_patch(
        lv,
        ~p"/orgs/#{org.slug}/projects/#{project.slug}/dashboard/flows?period=7d"
      )
    end

    test "invalid period falls back to default", %{conn: conn, org: org, project: project} do
      {:ok, _lv, html} =
        live(
          conn,
          ~p"/orgs/#{org.slug}/projects/#{project.slug}/dashboard/flows?period=bogus"
        )

      assert html =~ "Flows"
    end
  end

  describe "empty state" do
    test "renders stat cards with zero values when no executions exist", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/dashboard/flows")

      assert html =~ "Total Flows"
      assert html =~ "Executions"
      assert html =~ "Success Rate"
      assert html =~ "Avg Duration"
    end
  end

  # Helpers

  defp complete_execution!(flow) do
    execution = flow_execution_fixture(%{flow: flow})

    {:ok, execution} =
      execution
      |> Ecto.Changeset.change(%{
        status: "completed",
        duration_ms: 42,
        finished_at: DateTime.utc_now()
      })
      |> Repo.update()

    execution
  end
end
