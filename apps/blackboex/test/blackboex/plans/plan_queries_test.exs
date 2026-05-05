defmodule Blackboex.Plans.PlanQueriesTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Plans.PlanQueries

  setup [:create_user_and_org, :create_project]

  describe "for_project/2" do
    test "returns plans for the project ordered by inserted_at desc", %{project: project} do
      _other_project_plan =
        plan_fixture(%{
          project: Blackboex.ProjectsFixtures.project_fixture(),
          title: "Other"
        })

      _p1 = plan_fixture(%{project: project, title: "First"})
      :timer.sleep(10)
      p2 = plan_fixture(%{project: project, title: "Second"})

      [first | _] = Repo.all(PlanQueries.for_project(project.id))
      assert first.id == p2.id
    end

    test "filters by status", %{project: project} do
      _draft = plan_fixture(%{project: project, title: "D"})
      approved = approved_plan_fixture(%{project: project, title: "A"})

      result = Repo.all(PlanQueries.for_project(project.id, status: "approved"))
      assert Enum.map(result, & &1.id) == [approved.id]
    end

    test "filters by list of statuses", %{project: project} do
      draft = plan_fixture(%{project: project, status: "draft"})
      partial = partial_plan_fixture(%{project: project})

      result = Repo.all(PlanQueries.for_project(project.id, status: ["draft", "partial"]))
      ids = result |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([draft.id, partial.id])
    end
  end

  describe "active_for_project/1" do
    test "returns only :approved or :running plans", %{project: project} do
      _draft = plan_fixture(%{project: project})
      approved = approved_plan_fixture(%{project: project})

      assert [%{id: id}] = Repo.all(PlanQueries.active_for_project(project.id))
      assert id == approved.id
    end

    test "returns empty when no active plan", %{project: project} do
      _draft = plan_fixture(%{project: project})
      assert Repo.all(PlanQueries.active_for_project(project.id)) == []
    end
  end

  describe "tasks_for_plan/1 and done_tasks_for_plan/1" do
    test "returns tasks ordered by :order", %{project: project} do
      plan = plan_fixture(%{project: project})
      _t2 = plan_task_fixture(%{plan: plan, order: 1, title: "Second"})
      _t1 = plan_task_fixture(%{plan: plan, order: 0, title: "First"})

      tasks = Repo.all(PlanQueries.tasks_for_plan(plan.id))
      assert Enum.map(tasks, & &1.title) == ["First", "Second"]
    end

    test "done_tasks_for_plan returns only :done tasks", %{project: project} do
      plan = plan_fixture(%{project: project})
      done = plan_task_fixture(%{plan: plan, order: 0, status: "done"})
      _pending = plan_task_fixture(%{plan: plan, order: 1, status: "pending"})

      assert [%{id: id}] = Repo.all(PlanQueries.done_tasks_for_plan(plan.id))
      assert id == done.id
    end
  end

  describe "task_by_child_run_id/1" do
    test "looks up the PlanTask by its child Run id", %{project: project} do
      plan = plan_fixture(%{project: project})
      child_run_id = "33333333-3333-3333-3333-333333333333"

      task =
        plan_task_fixture(%{
          plan: plan,
          order: 0,
          status: "running",
          child_run_id: child_run_id
        })

      assert [%{id: id}] = Repo.all(PlanQueries.task_by_child_run_id(child_run_id))
      assert id == task.id
    end
  end
end
