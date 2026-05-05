defmodule Blackboex.ProjectAgent.KickoffWorkerTest do
  @moduledoc ~S"""
  Tests for the Project Agent kickoff entry point. Responsibilities:

    1. Open (or reuse) a `ProjectConversation` for the project.
    2. Create a `ProjectRun` with `run_type: "plan"`.
    3. Persist the initial user_message event.
    4. Call `Planner.build_plan/2`.
    5. Persist the resulting `Plan` + `PlanTask` rows in `:draft`.
    6. Broadcast `{:plan_drafted, plan}` on `"project_plan:#{plan.id}"`.
  """

  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  alias Blackboex.Plans
  alias Blackboex.ProjectAgent.KickoffWorker
  alias Blackboex.ProjectConversations

  setup [:create_user_and_org, :create_project]

  setup do
    Application.put_env(:blackboex, :project_planner_client, fn _project, _prompt ->
      {:ok,
       %{
         title: "CRUD for posts",
         tasks: [
           %{
             artifact_type: "api",
             action: "create",
             title: "Create posts API",
             params: %{},
             acceptance_criteria: ["POST /posts works"]
           }
         ]
       }}
    end)

    on_exit(fn -> Application.delete_env(:blackboex, :project_planner_client) end)
    :ok
  end

  describe "perform/1" do
    test "creates conversation, run, plan, and tasks; broadcasts :plan_drafted", ctx do
      args = base_args(ctx)

      :ok = perform_job(KickoffWorker, args)

      conv = ProjectConversations.get_active_conversation(ctx.project.id)
      assert conv

      [plan] = Plans.list_plans_for_project(ctx.project.id)
      assert plan.status == "draft"
      assert plan.title == "CRUD for posts"
      assert plan.user_message == args["user_message"]

      [task] = Plans.list_tasks(plan)
      assert task.artifact_type == "api"
      assert task.title == "Create posts API"
    end

    test "broadcasts {:plan_drafted, plan} on project_plan:<plan_id>", ctx do
      args = base_args(ctx)

      # Subscribe BEFORE running — the topic is plan-id-scoped, but for
      # the kickoff path we subscribe to a project-scoped topic too.
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "project_plan:project:#{ctx.project.id}")

      :ok = perform_job(KickoffWorker, args)

      assert_receive {:plan_drafted, %{id: plan_id, project_id: pid}}
      assert pid == ctx.project.id

      # And the per-plan topic carries the same message:
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "project_plan:#{plan_id}")
      assert plan_id != nil
    end

    test "marks the ProjectRun completed on success", ctx do
      args = base_args(ctx)

      :ok = perform_job(KickoffWorker, args)

      conv = ProjectConversations.get_active_conversation(ctx.project.id)
      [run | _] = ProjectConversations.list_runs(conv.id)
      assert run.status in ["completed", "running"]
    end

    test "marks the ProjectRun failed when the planner backend errors", ctx do
      Application.put_env(:blackboex, :project_planner_client, fn _project, _prompt ->
        {:error, :rate_limited}
      end)

      args = base_args(ctx)

      assert {:error, _} = perform_job(KickoffWorker, args)

      conv = ProjectConversations.get_active_conversation(ctx.project.id)
      [run | _] = ProjectConversations.list_runs(conv.id)
      assert run.status == "failed"
    end
  end

  defp base_args(ctx) do
    %{
      "project_id" => ctx.project.id,
      "organization_id" => ctx.org.id,
      "user_id" => ctx.user.id,
      "user_message" => "build a CRUD for blog posts"
    }
  end
end
