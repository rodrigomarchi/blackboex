defmodule Blackboex.Plans.MarkdownRendererTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Plans.MarkdownRenderer
  alias Blackboex.Plans.Plan

  setup [:create_user_and_org, :create_project, :create_plan]

  describe "render/1 — header" do
    test "renders the title and project id", %{plan: plan} do
      plan = Repo.preload(plan, :tasks)
      output = MarkdownRenderer.render(plan)

      assert output =~ "# " <> plan.title
      assert output =~ "Project ID: " <> plan.project_id
    end

    test "omits failure reason when nil", %{plan: plan} do
      plan = Repo.preload(plan, :tasks)
      output = MarkdownRenderer.render(plan)

      refute output =~ "Prior failure"
    end

    test "renders failure_reason when present", %{plan: plan} do
      {:ok, plan} =
        plan
        |> Plan.changeset(%{failure_reason: "task 2 boom"})
        |> Repo.update()

      plan = Repo.preload(plan, :tasks)
      output = MarkdownRenderer.render(plan)

      assert output =~ "Prior failure: task 2 boom"
    end
  end

  describe "render/1 — tasks" do
    test "renders 1-based task headers in `order` order", %{plan: plan} do
      _t1 =
        plan_task_fixture(%{
          plan: plan,
          order: 0,
          title: "Create posts API",
          artifact_type: "api",
          action: "create"
        })

      _t2 =
        plan_task_fixture(%{
          plan: plan,
          order: 1,
          title: "Create posts page",
          artifact_type: "page",
          action: "create"
        })

      plan = Repo.preload(plan, :tasks)
      output = MarkdownRenderer.render(plan)

      assert output =~ "## 1. Create posts API"
      assert output =~ "## 2. Create posts page"
      assert position(output, "## 1.") < position(output, "## 2.")
    end

    test "renders required structural bullets", %{plan: plan} do
      _t =
        plan_task_fixture(%{
          plan: plan,
          order: 0,
          title: "Edit posts page",
          artifact_type: "page",
          action: "edit",
          target_artifact_id: "11111111-1111-1111-1111-111111111111",
          params: %{"a" => 1},
          acceptance_criteria: ["it loads", "it renders"]
        })

      plan = Repo.preload(plan, :tasks)
      output = MarkdownRenderer.render(plan)

      assert output =~ "- artifact_type: page"
      assert output =~ "- action: edit"
      assert output =~ "- target_artifact_id: 11111111-1111-1111-1111-111111111111"
      assert output =~ "- params: "
      assert output =~ "- acceptance_criteria:"
      assert output =~ "  - it loads"
      assert output =~ "  - it renders"
    end

    test "target_artifact_id renders as 'nil' when absent", %{plan: plan} do
      _t = plan_task_fixture(%{plan: plan, target_artifact_id: nil})

      plan = Repo.preload(plan, :tasks)
      output = MarkdownRenderer.render(plan)

      assert output =~ "- target_artifact_id: nil"
    end

    test "acceptance_criteria empty renders as '(none)'", %{plan: plan} do
      _t = plan_task_fixture(%{plan: plan, acceptance_criteria: []})

      plan = Repo.preload(plan, :tasks)
      output = MarkdownRenderer.render(plan)

      assert output =~ "- acceptance_criteria:\n  - (none)"
    end
  end

  describe "render/1 — empty" do
    test "renders just the header when there are no tasks", %{plan: plan} do
      plan = Repo.preload(plan, :tasks)
      output = MarkdownRenderer.render(plan)

      refute output =~ "## "
      assert output =~ "# " <> plan.title
    end
  end

  defp position(haystack, needle) do
    case :binary.match(haystack, needle) do
      {start, _} -> start
      :nomatch -> -1
    end
  end
end
