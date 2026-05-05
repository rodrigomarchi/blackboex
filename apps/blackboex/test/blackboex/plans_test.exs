defmodule Blackboex.PlansTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Plans
  alias Blackboex.Plans.MarkdownRenderer

  setup [:create_user_and_org, :create_project]

  describe "list_plans_for_project/2 + get_plan!/1 + get_active_plan/1" do
    test "lists plans, gets by id, finds the active one", %{project: project} do
      _draft = plan_fixture(%{project: project})
      approved = approved_plan_fixture(%{project: project})

      ids = Plans.list_plans_for_project(project.id) |> Enum.map(& &1.id)
      assert approved.id in ids

      assert %{} = Plans.get_plan!(approved.id)
      assert %{id: id} = Plans.get_active_plan(project.id)
      assert id == approved.id
    end

    test "get_active_plan/1 returns nil when none", %{project: project} do
      _draft = plan_fixture(%{project: project})
      assert Plans.get_active_plan(project.id) == nil
    end
  end

  describe "create_draft_plan/3" do
    test "inserts plan + tasks atomically", %{user: user, project: project} do
      attrs = %{
        title: "Build CRUD",
        user_message: "Build a posts CRUD",
        markdown_body: "# Build CRUD\n",
        tasks: [
          %{artifact_type: "api", action: "create", title: "Create posts API"},
          %{artifact_type: "page", action: "create", title: "Create posts page"}
        ]
      }

      assert {:ok, plan} = Plans.create_draft_plan(project, user, attrs)
      assert plan.status == "draft"
      assert length(plan.tasks) == 2
      assert Enum.map(plan.tasks, & &1.order) == [0, 1]
    end
  end

  describe "approve_plan/3" do
    test "transitions :draft → :approved with valid markdown", %{user: user, project: project} do
      _t = plan_task_fixture(%{plan: plan_fixture(%{project: project}), order: 0})
      plan = Plans.get_active_plan(project.id) || plan_fixture(%{project: project})
      _t2 = plan_task_fixture(%{plan: plan, order: 0, title: "T"})

      plan = Plans.get_plan!(plan.id) |> Repo.preload(:tasks)
      md = MarkdownRenderer.render(plan)

      assert {:ok, approved} = Plans.approve_plan(plan, user, %{markdown_body: md})
      assert approved.status == "approved"
      assert approved.approved_by_user_id == user.id
      assert approved.approved_at != nil
    end

    test "rejects edits that violate invariants", %{user: user, project: project} do
      plan = plan_fixture(%{project: project})
      _t = plan_task_fixture(%{plan: plan, order: 0, artifact_type: "api"})
      plan = Plans.get_plan!(plan.id) |> Repo.preload(:tasks)

      md = MarkdownRenderer.render(plan)
      bad = String.replace(md, "- artifact_type: api", "- artifact_type: lambda")

      assert {:error, {:invalid_markdown_edit, violations}} =
               Plans.approve_plan(plan, user, %{markdown_body: bad})

      assert {:invalid_artifact_type, 0} in violations
    end

    test "rejects approval on a terminal plan", %{user: user, project: project} do
      plan = partial_plan_fixture(%{project: project})
      plan = Plans.get_plan!(plan.id) |> Repo.preload(:tasks)

      assert {:error, :already_terminal} =
               Plans.approve_plan(plan, user, %{markdown_body: plan.markdown_body})
    end
  end

  describe "state machine — plan transitions" do
    setup %{project: project} do
      plan = approved_plan_fixture(%{project: project})
      %{plan: Plans.get_plan!(plan.id)}
    end

    test ":approved → :running", %{plan: plan} do
      assert {:ok, %{status: "running"}} = Plans.mark_plan_running(plan)
    end

    test ":running → :done", %{plan: plan} do
      {:ok, plan} = Plans.mark_plan_running(plan)
      assert {:ok, %{status: "done"}} = Plans.mark_plan_done(plan)
    end

    test ":running → :partial with reason", %{plan: plan} do
      {:ok, plan} = Plans.mark_plan_running(plan)

      assert {:ok, %{status: "partial", failure_reason: "boom"}} =
               Plans.mark_plan_partial(plan, "boom")
    end

    test ":running → :failed with reason", %{plan: plan} do
      {:ok, plan} = Plans.mark_plan_running(plan)

      assert {:ok, %{status: "failed", failure_reason: "fatal"}} =
               Plans.mark_plan_failed(plan, "fatal")
    end

    test "any terminal state rejects further transitions", %{plan: plan} do
      {:ok, plan} = Plans.mark_plan_running(plan)
      {:ok, plan} = Plans.mark_plan_done(plan)

      assert {:error, :already_terminal} = Plans.mark_plan_running(plan)
      assert {:error, :already_terminal} = Plans.mark_plan_done(plan)
      assert {:error, :already_terminal} = Plans.mark_plan_partial(plan, "x")
      assert {:error, :already_terminal} = Plans.mark_plan_failed(plan, "x")
    end
  end

  describe "task transitions" do
    setup %{project: project} do
      plan = plan_fixture(%{project: project})
      task = plan_task_fixture(%{plan: plan, order: 0})
      %{plan: plan, task: task}
    end

    test "mark_task_running/2 sets child_run_id and started_at", %{task: task} do
      run_id = "44444444-4444-4444-4444-444444444444"
      assert {:ok, t} = Plans.mark_task_running(task, run_id)
      assert t.status == "running"
      assert t.child_run_id == run_id
      assert t.started_at != nil
    end

    test "mark_task_done/1", %{task: task} do
      {:ok, t} = Plans.mark_task_running(task, "55555555-5555-5555-5555-555555555555")
      assert {:ok, %{status: "done", finished_at: %DateTime{}}} = Plans.mark_task_done(t)
    end

    test "mark_task_failed/2 with reason", %{task: task} do
      assert {:ok, t} = Plans.mark_task_failed(task, "kaboom")
      assert t.status == "failed"
      assert t.error_message == "kaboom"
      assert t.finished_at != nil
    end
  end
end
