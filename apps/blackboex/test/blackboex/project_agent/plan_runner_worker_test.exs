defmodule Blackboex.ProjectAgent.PlanRunnerWorkerTest do
  @moduledoc """
  Tests for callback-driven advancement of an approved Plan. Each
  invocation:

    1. Loads the plan + tasks.
    2. If a task is `:running`, exits (waits for the broadcast adapter
       callback to advance us).
    3. Otherwise picks the next `:pending` task in `:order`, dispatches
       it, marks it `:running`, calls `BroadcastAdapter.subscribe/2`,
       touches the planner Run, and exits.
    4. When all tasks are terminal — `:done` if all `:done`/`:skipped`,
       `:partial` otherwise.
  """

  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  alias Blackboex.Plans
  alias Blackboex.Plans.MarkdownRenderer
  alias Blackboex.ProjectAgent.BroadcastAdapter
  alias Blackboex.ProjectAgent.PlanRunnerWorker
  alias Blackboex.Repo

  setup [:create_user_and_org, :create_project, :create_plan]

  describe "perform/1 — dispatching" do
    test "marks the plan :running on first invocation when :approved", ctx do
      plan = approve_with_one_task(ctx)

      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => plan.id})

      assert Plans.get_plan!(plan.id).status == "running"
    end

    test "transitions next pending task to :running with a child_run_id", ctx do
      plan = approve_with_one_task(ctx)

      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => plan.id})

      [task] = Plans.list_tasks(plan)
      assert task.status == "running"
      assert is_binary(task.child_run_id)
    end

    test "is a no-op when a task is already :running (waits for callback)", ctx do
      plan = approve_with_one_task(ctx)

      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => plan.id})
      [task_running] = Plans.list_tasks(plan)
      assert task_running.status == "running"

      # Second invocation must NOT re-dispatch.
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => plan.id})
      [task_still_running] = Plans.list_tasks(plan)
      assert task_still_running.id == task_running.id
      assert task_still_running.status == "running"
    end
  end

  describe "perform/1 — finalize" do
    test "marks plan :done when all tasks are :done", ctx do
      plan = approved_plan_fixture(Map.take(ctx, [:user, :org, :project]))
      [task] = Plans.list_tasks(plan)
      {:ok, _} = Plans.mark_task_running(task, Ecto.UUID.generate())
      task = Plans.get_task!(task.id)
      {:ok, _} = Plans.mark_task_done(task)

      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => plan.id})

      assert Plans.get_plan!(plan.id).status == "done"
    end

    test "marks plan :partial when at least one task :failed", ctx do
      plan = approve_with_two_tasks(ctx)
      [t1, t2] = Plans.list_tasks(plan) |> Enum.sort_by(& &1.order)
      {:ok, _} = Plans.mark_task_running(t1, Ecto.UUID.generate())
      {:ok, _} = Plans.mark_task_done(Plans.get_task!(t1.id))
      {:ok, _} = Plans.mark_task_running(t2, Ecto.UUID.generate())
      {:ok, _} = Plans.mark_task_failed(Plans.get_task!(t2.id), "boom")

      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => plan.id})

      reloaded = Plans.get_plan!(plan.id)
      assert reloaded.status == "partial"
      assert reloaded.failure_reason =~ "boom"
    end
  end

  describe "BroadcastAdapter integration — callback re-enqueue" do
    test "BroadcastAdapter.handle_terminal/4 advances task and re-enqueues runner", ctx do
      plan = approve_with_two_tasks(ctx)

      # Manually dispatch the first task as the runner would.
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => plan.id})
      [t1, t2] = Plans.list_tasks(plan) |> Enum.sort_by(& &1.order)
      assert t1.status == "running"
      assert t2.status == "pending"

      # Simulate the per-artifact agent terminal broadcast → adapter callback.
      assert :ok = BroadcastAdapter.handle_terminal(t1, plan, :completed, nil)

      assert Plans.get_task!(t1.id).status == "done"

      assert_enqueued(
        worker: PlanRunnerWorker,
        args: %{"plan_id" => plan.id}
      )
    end

    test "halt-on-failure: a failed task surfaces as plan :partial after finalize", ctx do
      plan = approve_with_two_tasks(ctx)

      # Dispatch + fail t1.
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => plan.id})
      [t1, _t2] = Plans.list_tasks(plan) |> Enum.sort_by(& &1.order)
      assert :ok = BroadcastAdapter.handle_terminal(t1, plan, :failed, "boom")

      # Now run the runner again — t2 is :pending. v1 dispatches it; the
      # plan is finalized as :partial only after every task is terminal.
      # Mimic t2 :failed too to drive finalize.
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => plan.id})
      [_, t2_running] = Plans.list_tasks(plan) |> Enum.sort_by(& &1.order)
      assert t2_running.status == "running"
      assert :ok = BroadcastAdapter.handle_terminal(t2_running, plan, :failed, "boom2")

      # Final pass finalizes.
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => plan.id})
      assert Plans.get_plan!(plan.id).status == "partial"
    end
  end

  describe "concurrent plan guard" do
    test "UNIQUE-partial constraint blocks a second concurrent active plan", ctx do
      _approved = approve_with_one_task(ctx)

      # Try to create a second draft + approve it simultaneously.
      second = plan_fixture(Map.take(ctx, [:user, :org, :project]))
      _t = plan_task_fixture(%{plan: second})

      result =
        Plans.approve_plan(second, ctx.user, %{
          markdown_body: MarkdownRenderer.render(Repo.preload(second, :tasks))
        })

      assert match?({:error, :concurrent_active_plan}, result) or
               match?({:error, %Ecto.Changeset{}}, result)
    end
  end

  defp approve_with_one_task(ctx) do
    plan = plan_fixture(Map.take(ctx, [:user, :org, :project]))
    _t = plan_task_fixture(%{plan: plan, artifact_type: "api", action: "create"})
    {:ok, approved} = Plans.approve_plan(plan, ctx.user, %{markdown_body: rendered(plan)})
    approved
  end

  defp approve_with_two_tasks(ctx) do
    plan = plan_fixture(Map.take(ctx, [:user, :org, :project]))
    _ = plan_task_fixture(%{plan: plan, artifact_type: "api", action: "create", order: 0})

    _ =
      plan_task_fixture(%{
        plan: plan,
        artifact_type: "flow",
        action: "create",
        order: 1,
        target_artifact_id: Ecto.UUID.generate()
      })

    {:ok, approved} = Plans.approve_plan(plan, ctx.user, %{markdown_body: rendered(plan)})
    approved
  end

  defp rendered(plan) do
    plan
    |> Repo.preload(:tasks)
    |> MarkdownRenderer.render()
  end
end
