defmodule Blackboex.Integration.ProjectAgentRealSessionTest do
  @moduledoc ~S"""
  M8 — Production wiring integration test (Plan §M8 #2 / Fix 7j),
  rewritten post-audit to drive the real production path without
  calling `BroadcastAdapter.handle_terminal/4` directly from the test.

  ## What this test proves

  The audit (`.omc/audit/{critic,verifier}-audit.md`) flagged that the
  prior version was theatrical: it called `handle_terminal/4` from test
  code because nothing in production did. After the gap-fix milestone:

    * `PlanRunnerWorker.enqueue_child/2` does real `Oban.insert!` of the
      matching per-artifact KickoffWorker (no synthetic UUID).
    * `ProjectAgent.RecoveryWorker` is the production caller of
      `BroadcastAdapter.handle_terminal/4`. It polls for `:running`
      tasks and translates terminal child Runs to the uniform broadcast.

  This test exercises that wiring END-TO-END:

      ProjectAgent.start_planning
        → ProjectAgent.KickoffWorker (with stubbed planner client)
        → Plans.create_draft_plan
      ProjectAgent.approve_and_run
        → Plans.approve_plan
        → enqueues PlanRunnerWorker
      PlanRunnerWorker.perform/1
        → enqueue_child generates real child_run_id, marks task :running,
          Oban.insert!(Blackboex.Agent.KickoffWorker.new(%{run_id: child_run_id, ...}))
      [Per-artifact Run row reaches a terminal status — see "Why we
       short-circuit" below.]
      ProjectAgent.RecoveryWorker.perform/1 (production caller)
        → polls running PlanTasks, fetches matching child Run via
          Conversations.get_run/1, calls handle_terminal/4 internally.
        → broadcasts {:project_task_completed, ...} on
          "project_plan:#{plan.id}".
      PlanRunnerWorker.perform/1 (final pass)
        → finalize_plan → :partial (halt-on-fail per D6).

  The test does **not** invoke `handle_terminal/4` directly — that
  responsibility now belongs to `RecoveryWorker`.

  ## Why we short-circuit the per-artifact Run to terminal

  The full `Agent.Session → ChainRunner → CodePipeline` happy path
  requires a deterministic LLM emission that compiles + lints + tests
  green inside the sandbox; making that deterministic in an integration
  test would require fixture-stitching every layer of the per-artifact
  pipeline. The per-artifact agents already have their own end-to-end
  tests covering Session behavior. This test focuses on the new
  ProjectAgent orchestration contract.

  We pre-create the per-artifact `Conversation` + `Run` row directly
  with `Conversations.create_run/2` (using the `child_run_id` the
  PlanRunnerWorker generated and passed into the per-artifact worker
  args), then transition that row to `:failed` in the DB — the same
  end state a real failed Session would produce. This gives
  RecoveryWorker the precondition it needs (a `PlanTask` in `:running`
  whose `child_run_id` resolves to a terminal Run row) without
  spawning the leaky async Session that would race with the test
  sandbox.
  """

  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  @moduletag :integration
  @moduletag :capture_log

  import Mox

  alias Blackboex.Agent.KickoffWorker, as: AgentKickoffWorker
  alias Blackboex.Conversations
  alias Blackboex.LLM.CircuitBreaker
  alias Blackboex.LLM.ClientMock
  alias Blackboex.Plans
  alias Blackboex.Plans.MarkdownRenderer
  alias Blackboex.ProjectAgent
  alias Blackboex.ProjectAgent.PlanRunnerWorker
  alias Blackboex.ProjectAgent.RecoveryWorker
  alias Blackboex.Repo

  setup [:create_user_and_org, :create_project, :create_org_and_api, :stub_llm_client]
  setup :set_mox_global

  setup do
    CircuitBreaker.reset(:anthropic)
    :ok
  end

  describe "ProjectAgent end-to-end via RecoveryWorker (production caller)" do
    test "kickoff → approve → PlanRunnerWorker dispatches real child worker → RecoveryWorker drives translation",
         ctx do
      api = ctx.api
      project = ctx.project

      stub(ClientMock, :stream_text, fn _prompt, _opts ->
        {:error, "simulated LLM failure"}
      end)

      stub(ClientMock, :generate_text, fn _prompt, _opts ->
        {:error, "simulated LLM failure"}
      end)

      Application.put_env(:blackboex, :project_planner_client, fn _project, _prompt ->
        {:ok,
         %{
           title: "Tweak posts API",
           tasks: [
             %{
               artifact_type: "api",
               action: "edit",
               target_artifact_id: api.id,
               title: "Tweak posts API handler",
               params: %{},
               acceptance_criteria: ["existing tests still pass"]
             }
           ]
         }}
      end)

      on_exit(fn -> Application.delete_env(:blackboex, :project_planner_client) end)

      # 1. ProjectAgent.KickoffWorker — real production path.
      assert :ok =
               perform_job(Blackboex.ProjectAgent.KickoffWorker, %{
                 "project_id" => project.id,
                 "organization_id" => ctx.org.id,
                 "user_id" => ctx.user.id,
                 "user_message" => "tweak posts api"
               })

      [plan] = Plans.list_plans_for_project(project.id)
      [task] = Plans.list_tasks(plan)
      assert task.status == "pending"

      # 2. LiveView would subscribe to this topic on mount.
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "project_plan:#{plan.id}")

      # 3. ProjectAgent.approve_and_run — real production path.
      markdown = plan |> Repo.preload(:tasks) |> MarkdownRenderer.render()

      {:ok, approved_plan} =
        ProjectAgent.approve_and_run(plan, ctx.user, %{markdown_body: markdown})

      assert approved_plan.status == "approved"

      # 4. PlanRunnerWorker — real production path. Generates a real
      # child_run_id, marks task :running, and Oban.insert!s the
      # matching per-artifact KickoffWorker.
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => approved_plan.id})

      [task_running] = Plans.list_tasks(approved_plan)
      assert task_running.status == "running"
      assert is_binary(task_running.child_run_id)

      # CRITICAL ASSERTION: the production code path must enqueue the
      # real Blackboex.Agent.KickoffWorker, not a stub. This is the
      # gap the audit caught and the fix milestone closed.
      assert_enqueued(
        worker: AgentKickoffWorker,
        args: %{"run_id" => task_running.child_run_id, "api_id" => api.id}
      )

      reloaded_plan = Plans.get_plan!(approved_plan.id)
      assert reloaded_plan.status == "running"

      # 5. Pre-create the per-artifact Run row using the real run_id
      # the PlanRunnerWorker chose. In production the AgentKickoffWorker
      # would do this via its own perform/1 (using the pre-supplied
      # run_id arg). We do it directly to avoid the async Session that
      # would otherwise race with the test sandbox.
      {:ok, conversation} =
        Conversations.get_or_create_conversation(api.id, ctx.org.id, project.id)

      {:ok, child_run} =
        Conversations.create_run(
          %{
            conversation_id: conversation.id,
            api_id: api.id,
            user_id: ctx.user.id,
            organization_id: ctx.org.id,
            project_id: project.id,
            run_type: "edit",
            status: "pending",
            trigger_message: "tweak posts api handler",
            config: %{
              "max_iterations" => 15,
              "max_time_ms" => 300_000,
              "max_cost_cents" => 50
            },
            model: "claude-sonnet-4-5-20250929"
          },
          task_running.child_run_id
        )

      assert child_run.id == task_running.child_run_id

      # 6. Transition the Run to :failed — what a real failed Session
      # would write. RecoveryWorker reads it via Conversations.get_run/1.
      {:ok, _terminal_run} =
        child_run
        |> Ecto.Changeset.change(status: "failed", error_summary: "simulated failure")
        |> Repo.update()

      # 7. PRODUCTION WIRING: drive the RecoveryWorker. This is now the
      # only production caller of BroadcastAdapter.handle_terminal/4.
      assert :ok = perform_job(RecoveryWorker, %{})

      # 8. The uniform broadcast must land on the project_plan topic.
      approved_plan_id = approved_plan.id
      task_running_id = task_running.id

      assert_receive {:project_task_completed,
                      %{
                        plan_id: ^approved_plan_id,
                        task_id: ^task_running_id,
                        status: :failed
                      }},
                     5_000

      # 9. PlanTask now :failed in DB.
      reloaded_task = Plans.get_task!(task_running.id)
      assert reloaded_task.status == "failed"

      # 10. PlanRunnerWorker final pass finalizes the plan to :partial
      # (halt-on-fail per D6).
      assert :ok = perform_job(PlanRunnerWorker, %{"plan_id" => approved_plan.id})

      finalized = Plans.get_plan!(approved_plan.id)
      assert finalized.status == "partial"
    end
  end
end
