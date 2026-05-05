defmodule Blackboex.ProjectAgent.BroadcastAdapterTest do
  @moduledoc ~S"""
  Tests for the uniform broadcast contract that bridges the four
  per-artifact KickoffWorker stacks into a single
  `{:project_task_completed, %{plan_id, task_id, status, error}}` shape on
  `"project_plan:#{plan.id}"`.
  """

  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  alias Blackboex.Plans
  alias Blackboex.ProjectAgent.BroadcastAdapter

  @project_plan_topic_prefix "project_plan:"

  setup [:create_user_and_org, :create_project, :create_plan]

  describe "subscribe/2" do
    test "returns :ok for each artifact_type", %{plan: plan} do
      org_id = Ecto.UUID.generate()

      cases = [
        %{artifact_type: "api", child_run_id: Ecto.UUID.generate(), target_artifact_id: nil},
        %{
          artifact_type: "flow",
          child_run_id: Ecto.UUID.generate(),
          target_artifact_id: Ecto.UUID.generate()
        },
        %{
          artifact_type: "page",
          child_run_id: Ecto.UUID.generate(),
          target_artifact_id: Ecto.UUID.generate(),
          params: %{"organization_id" => org_id}
        },
        %{
          artifact_type: "playground",
          child_run_id: Ecto.UUID.generate(),
          target_artifact_id: nil
        }
      ]

      for attrs <- cases do
        task = plan_task_fixture(Map.put(attrs, :plan, plan))
        assert :ok = BroadcastAdapter.subscribe(task, plan)
      end
    end

    test "is idempotent (multiple subscribes return :ok)", %{plan: plan} do
      task =
        plan_task_fixture(%{
          plan: plan,
          artifact_type: "api",
          child_run_id: Ecto.UUID.generate()
        })

      assert :ok = BroadcastAdapter.subscribe(task, plan)
      assert :ok = BroadcastAdapter.subscribe(task, plan)
    end
  end

  describe "handle_terminal/4 — uniform contract" do
    setup %{plan: plan} do
      task =
        plan_task_fixture(%{
          plan: plan,
          artifact_type: "api",
          child_run_id: Ecto.UUID.generate(),
          status: "running"
        })

      Phoenix.PubSub.subscribe(Blackboex.PubSub, @project_plan_topic_prefix <> plan.id)
      %{task: task}
    end

    test "broadcasts uniform :project_task_completed on success", %{plan: plan, task: task} do
      assert :ok = BroadcastAdapter.handle_terminal(task, plan, :completed, nil)

      assert_receive {:project_task_completed,
                      %{plan_id: plan_id, task_id: task_id, status: :completed, error: nil}}

      assert plan_id == plan.id
      assert task_id == task.id
    end

    test "broadcasts uniform :project_task_completed on failure with error", %{
      plan: plan,
      task: task
    } do
      assert :ok = BroadcastAdapter.handle_terminal(task, plan, :failed, "boom")

      assert_receive {:project_task_completed,
                      %{plan_id: plan_id, task_id: task_id, status: :failed, error: "boom"}}

      assert plan_id == plan.id
      assert task_id == task.id
    end

    test "marks task :done on :completed", %{plan: plan, task: task} do
      assert :ok = BroadcastAdapter.handle_terminal(task, plan, :completed, nil)

      assert Plans.get_task!(task.id).status == "done"
    end

    test "marks task :failed on :failed", %{plan: plan, task: task} do
      assert :ok = BroadcastAdapter.handle_terminal(task, plan, :failed, "kaboom")

      reloaded = Plans.get_task!(task.id)
      assert reloaded.status == "failed"
      assert reloaded.error_message == "kaboom"
    end

    test "is idempotent — second terminal call is a no-op", %{plan: plan, task: task} do
      assert :ok = BroadcastAdapter.handle_terminal(task, plan, :completed, nil)
      assert_receive {:project_task_completed, _}

      # Second call: task is already :done, so no second broadcast.
      assert :ok = BroadcastAdapter.handle_terminal(task, plan, :failed, "ignored")
      refute_receive {:project_task_completed, _}, 50

      # And the task stays :done.
      assert Plans.get_task!(task.id).status == "done"
    end

    test "re-enqueues PlanRunnerWorker for the plan to advance", %{plan: plan, task: task} do
      assert :ok = BroadcastAdapter.handle_terminal(task, plan, :completed, nil)

      assert_enqueued(
        worker: Blackboex.ProjectAgent.PlanRunnerWorker,
        args: %{"plan_id" => plan.id}
      )
    end
  end

  describe "translate_message/2 — translates each surface's actual tuple" do
    setup %{plan: plan} do
      task = plan_task_fixture(%{plan: plan, child_run_id: Ecto.UUID.generate()})
      %{task: task}
    end

    test "translates Agent :agent_completed → :completed", %{task: task} do
      run_id = task.child_run_id

      assert {:terminal, :completed, nil} =
               BroadcastAdapter.translate_message(
                 {:agent_completed, %{run_id: run_id, status: "completed"}},
                 task
               )
    end

    test "translates Agent :agent_failed → :failed with error", %{task: task} do
      run_id = task.child_run_id

      assert {:terminal, :failed, "boom"} =
               BroadcastAdapter.translate_message(
                 {:agent_failed, %{run_id: run_id, error: "boom"}},
                 task
               )
    end

    test "translates Flow/Page/Playground :run_completed → :completed", %{task: task} do
      run_id = task.child_run_id

      assert {:terminal, :completed, nil} =
               BroadcastAdapter.translate_message(
                 {:run_completed, %{run_id: run_id}},
                 task
               )
    end

    test "translates Flow/Page/Playground :run_failed with reason → :failed", %{task: task} do
      run_id = task.child_run_id

      assert {:terminal, :failed, "kapow"} =
               BroadcastAdapter.translate_message(
                 {:run_failed, %{run_id: run_id, reason: "kapow"}},
                 task
               )
    end

    test "ignores non-terminal messages", %{task: task} do
      assert :ignore =
               BroadcastAdapter.translate_message(
                 {:content_delta, %{run_id: task.child_run_id, delta: "..."}},
                 task
               )

      assert :ignore =
               BroadcastAdapter.translate_message(
                 {:run_started, %{run_id: task.child_run_id}},
                 task
               )
    end

    test "ignores messages whose run_id does not match this task", %{task: task} do
      other = Ecto.UUID.generate()

      assert :ignore =
               BroadcastAdapter.translate_message(
                 {:agent_completed, %{run_id: other, status: "completed"}},
                 task
               )
    end
  end

  describe "topic_for/1" do
    test "api -> per-run topic" do
      run_id = Ecto.UUID.generate()
      task = %Blackboex.Plans.PlanTask{artifact_type: "api", child_run_id: run_id}
      assert BroadcastAdapter.topic_for(task) == "run:#{run_id}"
    end

    test "flow -> flow agent topic" do
      flow_id = Ecto.UUID.generate()
      task = %Blackboex.Plans.PlanTask{artifact_type: "flow", target_artifact_id: flow_id}
      assert BroadcastAdapter.topic_for(task) == "flow_agent:flow:#{flow_id}"
    end

    test "page -> org-scoped page agent topic" do
      page_id = Ecto.UUID.generate()
      org_id = Ecto.UUID.generate()

      task = %Blackboex.Plans.PlanTask{
        artifact_type: "page",
        target_artifact_id: page_id,
        params: %{"organization_id" => org_id}
      }

      assert BroadcastAdapter.topic_for(task) == "page_agent:#{org_id}:page:#{page_id}"
    end

    test "playground -> per-run topic" do
      run_id = Ecto.UUID.generate()
      task = %Blackboex.Plans.PlanTask{artifact_type: "playground", child_run_id: run_id}
      assert BroadcastAdapter.topic_for(task) == "playground_agent:run:#{run_id}"
    end
  end
end
