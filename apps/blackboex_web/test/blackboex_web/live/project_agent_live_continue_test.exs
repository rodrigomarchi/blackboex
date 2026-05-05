defmodule BlackboexWeb.ProjectAgentLiveContinueTest do
  @moduledoc """
  Tests for the M7 "Continue from where you stopped" button on the
  Project Agent LiveView. The button is rendered only for plans in
  `:partial` or `:failed` status. Clicking it triggers
  `Plans.start_continuation/2` and enqueues the `KickoffWorker` in
  continuation mode.
  """

  use BlackboexWeb.ConnCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  import Phoenix.LiveViewTest

  alias Blackboex.Plans
  alias Blackboex.ProjectAgent.KickoffWorker

  @moduletag :liveview

  setup [:register_and_log_in_user, :stub_llm_client]

  setup %{user: user} do
    org = org_fixture(%{user: user})
    project = project_fixture(%{user: user, org: org})
    %{org: org, project: project}
  end

  defp agent_path(org, project),
    do: ~p"/orgs/#{org.slug}/projects/#{project.slug}/agent"

  describe "Continue button visibility" do
    test "renders for a :partial plan", %{conn: conn, org: org, project: project} do
      _partial = partial_plan_fixture(%{project: project})

      {:ok, view, html} = live(conn, agent_path(org, project))

      assert html =~ "Continue from where you stopped"
      assert_has(view, "button[phx-click=\"continue_from_partial\"]")
    end

    test "renders for a :failed plan", %{
      conn: conn,
      org: org,
      project: project
    } do
      plan = plan_fixture(%{project: project, status: "failed", failure_reason: "boom"})
      _ = plan_task_fixture(%{plan: plan, status: "failed", error_message: "boom"})

      {:ok, view, html} = live(conn, agent_path(org, project))

      assert html =~ "Continue from where you stopped"
      assert_has(view, "button[phx-click=\"continue_from_partial\"]")
    end

    test "is hidden for a :draft plan", %{conn: conn, org: org, project: project} do
      _draft = plan_fixture(%{project: project, status: "draft"})

      {:ok, _view, html} = live(conn, agent_path(org, project))
      refute html =~ "Continue from where you stopped"
    end

    test "is hidden for an :approved plan", %{conn: conn, org: org, project: project} do
      _approved = approved_plan_fixture(%{project: project})

      {:ok, _view, html} = live(conn, agent_path(org, project))
      refute html =~ "Continue from where you stopped"
    end

    test "is hidden for a :done plan", %{
      conn: conn,
      org: org,
      project: project,
      user: user
    } do
      approved = approved_plan_fixture(%{project: project})
      {:ok, running} = Plans.mark_plan_running(approved)
      {:ok, _done} = Plans.mark_plan_done(running)

      _ = user

      {:ok, _view, html} = live(conn, agent_path(org, project))
      refute html =~ "Continue from where you stopped"
    end
  end

  describe "continue_from_partial event" do
    test "creates a draft continuation plan and enqueues KickoffWorker in continuation mode",
         %{conn: conn, org: org, project: project} do
      partial = partial_plan_fixture(%{project: project})

      {:ok, view, _html} = live(conn, agent_path(org, project))

      view
      |> element("button[phx-click=\"continue_from_partial\"]")
      |> render_click()

      # A new draft plan exists with parent_plan_id linking to the partial
      plans = Plans.list_plans_for_project(project.id)
      draft = Enum.find(plans, &(&1.status == "draft"))
      assert draft
      assert draft.parent_plan_id == partial.id

      # Continuation kickoff job enqueued
      assert_enqueued(
        worker: KickoffWorker,
        args: %{
          "continuation" => true,
          "parent_plan_id" => partial.id,
          "plan_id" => draft.id,
          "project_id" => project.id
        }
      )
    end

    test "swaps the rendered plan to the new draft", %{
      conn: conn,
      org: org,
      project: project
    } do
      _partial = partial_plan_fixture(%{project: project})

      {:ok, view, _html} = live(conn, agent_path(org, project))

      view
      |> element("button[phx-click=\"continue_from_partial\"]")
      |> render_click()

      html = render(view)
      # Editor for the new draft is visible (status uppercased in the
      # editor header).
      assert html =~ "draft"
    end
  end
end
