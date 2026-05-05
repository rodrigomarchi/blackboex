defmodule Blackboex.Plans.AddPlannerTasksToContinuationTest do
  @moduledoc """
  Tests for `Plans.add_planner_tasks_to_continuation/2` — appends new
  `:pending` tasks (produced by the Planner) to an existing continuation
  draft plan that already has parent's `:done` tasks copied as
  `:skipped`.
  """
  use Blackboex.DataCase, async: true

  alias Blackboex.Plans

  setup [:create_user_and_org, :create_project]

  describe "add_planner_tasks_to_continuation/2" do
    test "appends new :pending tasks to a draft continuation plan after :skipped tasks",
         %{user: user, project: project} do
      parent = partial_plan_fixture(%{project: project})
      {:ok, draft} = Plans.start_continuation(parent, user)

      skipped = Plans.list_tasks(draft) |> Enum.filter(&(&1.status == "skipped"))
      assert skipped != []

      new_tasks = [
        %{
          artifact_type: "api",
          action: "create",
          title: "New task A",
          params: %{},
          acceptance_criteria: ["A criterion"]
        },
        %{
          artifact_type: "page",
          action: "create",
          title: "New task B",
          params: %{},
          acceptance_criteria: []
        }
      ]

      assert {:ok, plan_with_full_tasks} =
               Plans.add_planner_tasks_to_continuation(draft, new_tasks)

      tasks = Plans.list_tasks(plan_with_full_tasks)
      pending = Enum.filter(tasks, &(&1.status == "pending"))
      assert length(pending) == 2

      titles = pending |> Enum.sort_by(& &1.order) |> Enum.map(& &1.title)
      assert titles == ["New task A", "New task B"]
    end

    test "appended :pending tasks have orders strictly greater than :skipped tasks",
         %{user: user, project: project} do
      parent = partial_plan_fixture(%{project: project})
      {:ok, draft} = Plans.start_continuation(parent, user)

      skipped_orders =
        draft
        |> Plans.list_tasks()
        |> Enum.filter(&(&1.status == "skipped"))
        |> Enum.map(& &1.order)

      max_skipped = Enum.max(skipped_orders, fn -> -1 end)

      new_tasks = [
        %{
          artifact_type: "flow",
          action: "create",
          title: "Flow X",
          params: %{},
          acceptance_criteria: []
        }
      ]

      {:ok, plan} = Plans.add_planner_tasks_to_continuation(draft, new_tasks)

      [pending] = plan |> Plans.list_tasks() |> Enum.filter(&(&1.status == "pending"))
      assert pending.order > max_skipped
    end

    test "rejects appending to a non-draft plan", %{project: project} do
      approved = approved_plan_fixture(%{project: project})

      assert {:error, :not_draft} =
               Plans.add_planner_tasks_to_continuation(approved, [
                 %{
                   artifact_type: "api",
                   action: "create",
                   title: "x",
                   params: %{},
                   acceptance_criteria: []
                 }
               ])
    end

    test "empty task list returns the plan unchanged", %{user: user, project: project} do
      parent = partial_plan_fixture(%{project: project})
      {:ok, draft} = Plans.start_continuation(parent, user)

      tasks_before = Plans.list_tasks(draft)
      assert {:ok, plan} = Plans.add_planner_tasks_to_continuation(draft, [])
      tasks_after = Plans.list_tasks(plan)
      assert length(tasks_after) == length(tasks_before)
    end
  end
end
