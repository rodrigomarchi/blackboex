defmodule Blackboex.Integration.ProjectAgentE2ETest do
  @moduledoc """
  M8 — Stubbed-LLM end-to-end integration test for the Project Agent.

  Exercises the full happy path with the planner LLM stubbed via the
  documented `:project_planner_client` test seam:

    1. `start_planning/3` opens a `ProjectConversation` + `ProjectRun`
       and enqueues `KickoffWorker`.
    2. `KickoffWorker` runs (via `perform_job/2`), invokes the stubbed
       planner, persists `Plan` + `PlanTask` rows in `:draft`, and
       broadcasts `{:plan_drafted, _}` on the project + plan topics.
    3. `approve_and_run/3` re-validates the markdown body, transitions
       the plan `:draft → :approved`, and enqueues `PlanRunnerWorker`.
    4. `PlanRunnerWorker` dispatches each `PlanTask` and marks it
       `:running`; the test simulates per-artifact agent terminals via
       `BroadcastAdapter.handle_terminal/4` (per-artifact agents are NOT
       executed here — that's the job of the companion
       `project_agent_real_session_test.exs`).
    5. The plan finalizes to `:done` when every task is `:done`.
    6. A failure-path branch flips a task to `:failed` and asserts plan
       `:partial`; `start_continuation/2` then produces a new draft with
       `parent_plan_id` set, and the continuation `KickoffWorker`
       (continuation mode) appends the new `:pending` tasks via
       `Plans.add_planner_tasks_to_continuation/2`.
  """

  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  @moduletag :integration
  @moduletag :capture_log

  alias Blackboex.Plans
  alias Blackboex.Plans.MarkdownRenderer
  alias Blackboex.ProjectAgent
  alias Blackboex.ProjectAgent.BroadcastAdapter
  alias Blackboex.ProjectAgent.KickoffWorker
  alias Blackboex.ProjectAgent.PlanRunnerWorker
  alias Blackboex.ProjectConversations
  alias Blackboex.Repo

  # Plan §M8 calls for `:register_and_log_in_user`, which lives only on
  # `ConnCase`. The e2e test does not need a Plug.Conn — `:create_user_and_org`
  # plus `:create_project` plus `:stub_llm_client` cover the same setup
  # surface (user, org, project, stubbed LLM) without requiring `ConnCase`.
  setup [:create_user_and_org, :create_project, :stub_llm_client]

  setup do
    # Stub the planner backend with a deterministic 2-task plan covering
    # two distinct artifact types. Two tasks let us exercise sequential
    # dispatch + per-task callback advancement.
    Application.put_env(:blackboex, :project_planner_client, fn _project, _prompt ->
      {:ok,
       %{
         title: "Build blog CRUD",
         tasks: [
           %{
             artifact_type: "api",
             action: "create",
             title: "Create posts API",
             params: %{},
             acceptance_criteria: ["POST /posts works"]
           },
           %{
             # `playground` (and `api`) route in `BroadcastAdapter.topic_for/1`
             # on `child_run_id`, which is always set on `:running`. `page`
             # and `flow` route on `target_artifact_id` which is nil for
             # `:create` actions — using those here would require a
             # pre-existing artifact, which is out of scope for the stubbed
             # e2e (Test §2 covers a real `:edit` against a fixture API).
             artifact_type: "playground",
             action: "create",
             title: "Create demo playground",
             params: %{},
             acceptance_criteria: ["compiles"]
           }
         ]
       }}
    end)

    on_exit(fn -> Application.delete_env(:blackboex, :project_planner_client) end)
    :ok
  end

  describe "happy path: plan → approve → dispatch → done" do
    test "drives a stubbed plan from kickoff to :done end-to-end", ctx do
      # 1. Submit user message via the public facade.
      assert {:ok, conversation, run} =
               ProjectAgent.start_planning(ctx.project, ctx.user, "build blog CRUD")

      assert run.run_type == "plan"
      assert run.trigger_message == "build blog CRUD"

      assert ProjectConversations.get_active_conversation(ctx.project.id).id == conversation.id

      # 2. Run the enqueued KickoffWorker — the stubbed planner emits the
      # plan; KickoffWorker persists it as :draft.
      kickoff_args = %{
        "project_id" => ctx.project.id,
        "organization_id" => ctx.org.id,
        "user_id" => ctx.user.id,
        "user_message" => "build blog CRUD"
      }

      assert :ok = perform_job(KickoffWorker, kickoff_args)

      [plan] = Plans.list_plans_for_project(ctx.project.id)
      assert plan.status == "draft"
      assert plan.title == "Build blog CRUD"
      tasks = Plans.list_tasks(plan)
      assert length(tasks) == 2
      assert Enum.all?(tasks, &(&1.status == "pending"))

      # 3. Approve the plan via the public facade.
      markdown = plan |> Repo.preload(:tasks) |> MarkdownRenderer.render()

      assert {:ok, approved} =
               ProjectAgent.approve_and_run(plan, ctx.user, %{markdown_body: markdown})

      assert approved.status == "approved"

      assert_enqueued(worker: PlanRunnerWorker, args: %{"plan_id" => approved.id})

      # 4. Drive the runner: each pass dispatches the next pending task.
      # Pass 1: dispatches task 1 (api).
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => approved.id})
      [t1, t2] = Plans.list_tasks(approved) |> Enum.sort_by(& &1.order)
      assert t1.status == "running"
      assert is_binary(t1.child_run_id)
      assert t2.status == "pending"

      # 5. Simulate task-1 completion via BroadcastAdapter (the runner's
      # callback seam). Adapter marks task :done and re-enqueues the
      # PlanRunnerWorker.
      assert :ok = BroadcastAdapter.handle_terminal(t1, approved, :completed, nil)
      assert Plans.get_task!(t1.id).status == "done"
      assert_enqueued(worker: PlanRunnerWorker, args: %{"plan_id" => approved.id})

      # Pass 2: dispatches task 2 (page).
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => approved.id})
      t2_running = Plans.get_task!(t2.id)
      assert t2_running.status == "running"

      # Simulate task-2 completion.
      assert :ok = BroadcastAdapter.handle_terminal(t2_running, approved, :completed, nil)
      assert Plans.get_task!(t2.id).status == "done"

      # Final pass: finalize.
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => approved.id})
      assert Plans.get_plan!(approved.id).status == "done"
    end
  end

  describe "failure path: a failed task transitions plan to :partial; continuation re-plans" do
    test "task failure → plan :partial; start_continuation drafts a child plan", ctx do
      # Drive plan to :approved with two tasks via the kickoff path.
      kickoff_args = %{
        "project_id" => ctx.project.id,
        "organization_id" => ctx.org.id,
        "user_id" => ctx.user.id,
        "user_message" => "build blog CRUD"
      }

      assert :ok = perform_job(KickoffWorker, kickoff_args)
      [plan] = Plans.list_plans_for_project(ctx.project.id)
      markdown = plan |> Repo.preload(:tasks) |> MarkdownRenderer.render()
      {:ok, approved} = ProjectAgent.approve_and_run(plan, ctx.user, %{markdown_body: markdown})

      # Dispatch + complete task 1.
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => approved.id})
      [t1, _t2] = Plans.list_tasks(approved) |> Enum.sort_by(& &1.order)
      :ok = BroadcastAdapter.handle_terminal(t1, approved, :completed, nil)

      # Dispatch task 2 then fail it.
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => approved.id})
      [_, t2_running] = Plans.list_tasks(approved) |> Enum.sort_by(& &1.order)
      assert t2_running.status == "running"
      :ok = BroadcastAdapter.handle_terminal(t2_running, approved, :failed, "boom")

      # Final pass finalizes plan as :partial (some tasks done, at least one failed).
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => approved.id})
      partial = Plans.get_plan!(approved.id)
      assert partial.status == "partial"
      assert partial.failure_reason =~ "boom"

      # 6. start_continuation/2 → new :draft plan with parent_plan_id set
      # and the parent's :done tasks copied as :skipped.
      assert {:ok, continuation_draft} = Plans.start_continuation(partial, ctx.user)
      assert continuation_draft.status == "draft"
      assert continuation_draft.parent_plan_id == partial.id

      [skipped] = Plans.list_tasks(continuation_draft) |> Enum.filter(&(&1.status == "skipped"))
      assert skipped.title == t1.title

      # The continuation KickoffWorker (continuation mode) appends the new
      # :pending tasks. Drive it directly to confirm full continuation
      # round-trip.
      continuation_args = %{
        "project_id" => ctx.project.id,
        "organization_id" => ctx.org.id,
        "user_id" => ctx.user.id,
        "user_message" => partial.user_message,
        "continuation" => true,
        "parent_plan_id" => partial.id,
        "plan_id" => continuation_draft.id
      }

      assert :ok = perform_job(KickoffWorker, continuation_args)

      tasks_after = Plans.list_tasks(continuation_draft)
      pending = Enum.filter(tasks_after, &(&1.status == "pending"))
      skipped = Enum.filter(tasks_after, &(&1.status == "skipped"))

      assert length(skipped) == 1
      assert pending != []
    end
  end
end
