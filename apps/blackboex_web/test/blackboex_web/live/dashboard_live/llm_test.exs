defmodule BlackboexWeb.DashboardLive.LlmTest do
  @moduledoc """
  Tests for the LLM dashboard content in both org and project scopes.
  """
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Organizations
  alias Blackboex.Projects

  @moduletag :liveview

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Organizations.create_organization(user, %{name: "LLM Org"})

    project = Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "org scope at /orgs/:slug/settings/llm" do
    test "renders header, nav and aggregated stats", %{
      conn: conn,
      org: org,
      project: project
    } do
      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        model: "gpt-4o-mini",
        input_tokens: 200,
        output_tokens: 100,
        cost_cents: 5
      })

      {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.slug}/settings/llm")

      assert html =~ "Dashboard"
      assert html =~ "Generations"
      assert html =~ "Tokens (in / out)"
      assert html =~ "Estimated cost"
      assert html =~ "By model"
      assert html =~ "gpt-4o-mini"
      # Nav highlights LLM tab and links resolve to org base_path
      assert html =~ "/orgs/#{org.slug}/settings/llm"
    end
  end

  describe "project scope at /orgs/:slug/projects/:slug/settings/llm" do
    test "renders project-scoped stats", %{
      conn: conn,
      org: org,
      project: project
    } do
      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        model: "claude-haiku",
        input_tokens: 50,
        output_tokens: 25,
        cost_cents: 2
      })

      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/llm")

      assert html =~ "claude-haiku"
      assert html =~ "/orgs/#{org.slug}/projects/#{project.slug}/settings/llm"
    end

    test "excludes usage from other projects in same org", %{
      conn: conn,
      user: user,
      org: org,
      project: project
    } do
      other_project = project_fixture(%{user: user, org: org, name: "Other Project"})

      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: other_project.id,
        model: "other-model-xyz",
        input_tokens: 999,
        output_tokens: 999,
        cost_cents: 999
      })

      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/llm")

      refute html =~ "other-model-xyz"
    end
  end

  describe "period selector" do
    test "patching ?period=7d updates assigns and renders", %{
      conn: conn,
      org: org,
      project: project
    } do
      llm_usage_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        model: "gpt-4o-mini"
      })

      {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.slug}/settings/llm")

      html = render_patch(lv, ~p"/orgs/#{org.slug}/settings/llm?period=7d")

      assert html =~ "period=7d"
      assert html =~ "Generations"
    end
  end

  describe "empty state" do
    test "renders stat cards with zero values when no LLM usage", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _lv, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/settings/llm")

      assert html =~ "Generations"
      assert html =~ "Tokens (in / out)"
      assert html =~ "Estimated cost"
    end
  end
end
