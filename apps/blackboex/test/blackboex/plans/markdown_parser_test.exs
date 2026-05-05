defmodule Blackboex.Plans.MarkdownParserTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Plans.MarkdownParser
  alias Blackboex.Plans.MarkdownRenderer

  setup [:create_user_and_org, :create_project, :create_plan]

  describe "parse_and_validate/2 — round-trip" do
    test "render → parse preserves structural fields", %{plan: plan} do
      _t1 =
        plan_task_fixture(%{
          plan: plan,
          order: 0,
          title: "T1",
          artifact_type: "api",
          action: "create",
          target_artifact_id: nil,
          params: %{"verb" => "POST"},
          acceptance_criteria: ["it returns 201"]
        })

      _t2 =
        plan_task_fixture(%{
          plan: plan,
          order: 1,
          title: "T2",
          artifact_type: "page",
          action: "edit",
          target_artifact_id: "22222222-2222-2222-2222-222222222222",
          params: %{},
          acceptance_criteria: []
        })

      plan = Repo.preload(plan, :tasks)
      md = MarkdownRenderer.render(plan)

      assert {:ok, %{title: title, tasks: tasks}} = MarkdownParser.parse_and_validate(md, plan)
      assert title == plan.title
      assert length(tasks) == 2

      [p1, p2] = tasks
      assert p1.artifact_type == "api"
      assert p1.action == "create"
      assert p1.target_artifact_id == nil
      assert p1.title == "T1"
      assert p1.params == %{"verb" => "POST"}
      assert p1.acceptance_criteria == ["it returns 201"]

      assert p2.artifact_type == "page"
      assert p2.action == "edit"
      assert p2.target_artifact_id == "22222222-2222-2222-2222-222222222222"
      assert p2.acceptance_criteria == []
    end

    test "accepts edits to acceptance_criteria", %{plan: plan} do
      _t = plan_task_fixture(%{plan: plan, order: 0, acceptance_criteria: ["a"]})
      plan = Repo.preload(plan, :tasks)
      md = MarkdownRenderer.render(plan)

      edited = String.replace(md, "  - a", "  - a\n  - b\n  - c")
      assert {:ok, %{tasks: [task]}} = MarkdownParser.parse_and_validate(edited, plan)
      assert task.acceptance_criteria == ["a", "b", "c"]
    end

    test "accepts edits to title", %{plan: plan} do
      _t = plan_task_fixture(%{plan: plan, order: 0, title: "Old"})
      plan = Repo.preload(plan, :tasks)
      md = MarkdownRenderer.render(plan)

      edited = String.replace(md, "## 1. Old", "## 1. New title here")
      assert {:ok, %{tasks: [task]}} = MarkdownParser.parse_and_validate(edited, plan)
      assert task.title == "New title here"
    end

    test "accepts reordering tasks (no :order_changed in v1)", %{plan: plan} do
      t1 = plan_task_fixture(%{plan: plan, order: 0, title: "First"})
      t2 = plan_task_fixture(%{plan: plan, order: 1, title: "Second"})

      plan = Repo.preload(plan, :tasks)

      md = MarkdownRenderer.render(plan)
      # Manually swap the two `## N.` blocks so the second task comes first.
      assert {:ok, %{tasks: [_, _]} = parsed} = swap_and_parse(md, plan, t1, t2)
      assert Enum.map(parsed.tasks, & &1.title) == ["Second", "First"]
    end
  end

  describe "parse_and_validate/2 — violations" do
    test "rejects invalid artifact_type", %{plan: plan} do
      _t = plan_task_fixture(%{plan: plan, order: 0, artifact_type: "api"})
      plan = Repo.preload(plan, :tasks)
      md = MarkdownRenderer.render(plan)
      bad = String.replace(md, "- artifact_type: api", "- artifact_type: lambda")

      assert {:error, violations} = MarkdownParser.parse_and_validate(bad, plan)
      assert {:invalid_artifact_type, 0} in violations
    end

    test "rejects invalid action", %{plan: plan} do
      _t = plan_task_fixture(%{plan: plan, order: 0, action: "create"})
      plan = Repo.preload(plan, :tasks)
      md = MarkdownRenderer.render(plan)
      bad = String.replace(md, "- action: create", "- action: zap")

      assert {:error, violations} = MarkdownParser.parse_and_validate(bad, plan)
      assert {:invalid_action, 0} in violations
    end

    test "rejects target_artifact_id change for an edit task", %{plan: plan} do
      original_id = "11111111-1111-1111-1111-111111111111"

      _t =
        plan_task_fixture(%{
          plan: plan,
          order: 0,
          action: "edit",
          target_artifact_id: original_id
        })

      plan = Repo.preload(plan, :tasks)
      md = MarkdownRenderer.render(plan)

      tampered =
        String.replace(
          md,
          "- target_artifact_id: " <> original_id,
          "- target_artifact_id: 99999999-9999-9999-9999-999999999999"
        )

      assert {:error, violations} = MarkdownParser.parse_and_validate(tampered, plan)
      assert {:target_artifact_changed, 0} in violations
    end

    test "rejects renaming a structural field", %{plan: plan} do
      _t = plan_task_fixture(%{plan: plan, order: 0})
      plan = Repo.preload(plan, :tasks)
      md = MarkdownRenderer.render(plan)
      bad = String.replace(md, "- artifact_type:", "- kind:")

      assert {:error, violations} = MarkdownParser.parse_and_validate(bad, plan)
      assert Enum.any?(violations, &match?({:structural_field_renamed, :artifact_type}, &1))
    end

    test "rejects markdown without a `# title` heading", %{plan: plan} do
      plan = Repo.preload(plan, :tasks)

      assert {:error, [{:structural_field_renamed, :title}]} =
               MarkdownParser.parse_and_validate("no title here", plan)
    end
  end

  defp swap_and_parse(md, plan, _t1, _t2) do
    [head, t1_block, t2_block] =
      Regex.split(~r/(?=^## \d+\.)/m, md, parts: 3)

    swapped = head <> t2_block <> t1_block
    MarkdownParser.parse_and_validate(swapped, plan)
  end
end
