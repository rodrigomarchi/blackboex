defmodule Blackboex.Plans.StartContinuationTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Plans

  setup [:create_user_and_org, :create_project]

  describe "start_continuation/2 — happy path" do
    test "creates a draft child plan with parent_plan_id and copies :done tasks as :skipped",
         %{user: user, project: project} do
      parent = partial_plan_fixture(%{project: project})
      parent = Plans.get_plan!(parent.id) |> Repo.preload(:tasks)

      done_count = Enum.count(parent.tasks, &(&1.status == "done"))
      assert done_count >= 1

      assert {:ok, child} = Plans.start_continuation(parent, user)
      assert child.status == "draft"
      assert child.parent_plan_id == parent.id

      child_tasks = Plans.list_tasks(child)
      skipped = Enum.filter(child_tasks, &(&1.status == "skipped"))
      assert length(skipped) == done_count
    end

    test "the new draft does not collide with the parent's UNIQUE-partial slot",
         %{user: user, project: project} do
      parent = partial_plan_fixture(%{project: project})
      parent = Plans.get_plan!(parent.id) |> Repo.preload(:tasks)

      assert {:ok, _child} = Plans.start_continuation(parent, user)
      # parent stays :partial; new is :draft → both excluded from active idx
      assert nil == Plans.get_active_plan(project.id)
    end
  end

  describe "start_continuation/2 — parent_still_active" do
    test "rejects continuation while parent is :draft", %{user: user, project: project} do
      parent = plan_fixture(%{project: project})
      assert {:error, :parent_still_active} = Plans.start_continuation(parent, user)
    end

    test "rejects continuation while parent is :approved", %{user: user, project: project} do
      parent = approved_plan_fixture(%{project: project})
      assert {:error, :parent_still_active} = Plans.start_continuation(parent, user)
    end

    test "rejects continuation while parent is :running", %{user: user, project: project} do
      parent = approved_plan_fixture(%{project: project})
      {:ok, parent} = Plans.mark_plan_running(parent)
      assert {:error, :parent_still_active} = Plans.start_continuation(parent, user)
    end

    test "rejects continuation while parent is :done", %{user: user, project: project} do
      parent = approved_plan_fixture(%{project: project})
      {:ok, parent} = Plans.mark_plan_running(parent)
      {:ok, parent} = Plans.mark_plan_done(parent)
      assert {:error, :parent_still_active} = Plans.start_continuation(parent, user)
    end
  end

  describe "start_continuation/2 — :failed parent allowed" do
    test "creates a draft child for a :failed parent", %{user: user, project: project} do
      parent = approved_plan_fixture(%{project: project})
      {:ok, parent} = Plans.mark_plan_running(parent)
      {:ok, parent} = Plans.mark_plan_failed(parent, "boom")

      assert {:ok, child} = Plans.start_continuation(parent, user)
      assert child.status == "draft"
      assert child.parent_plan_id == parent.id
    end
  end
end
