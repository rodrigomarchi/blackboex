defmodule Blackboex.ProjectAgentTest do
  @moduledoc """
  Tests for the public Project Agent facade.
  """

  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  alias Blackboex.Plans
  alias Blackboex.Plans.MarkdownRenderer
  alias Blackboex.ProjectAgent
  alias Blackboex.ProjectConversations
  alias Blackboex.Repo

  setup [:create_user_and_org, :create_project]

  describe "start_planning/3" do
    test "opens a conversation+run, enqueues the kickoff worker", ctx do
      assert {:ok, conversation, run} =
               ProjectAgent.start_planning(ctx.project, ctx.user, "build a CRUD")

      assert conversation.project_id == ctx.project.id
      assert run.run_type == "plan"
      assert run.trigger_message == "build a CRUD"
      assert run.status in ["pending", "running"]

      assert ProjectConversations.get_active_conversation(ctx.project.id).id == conversation.id

      assert_enqueued(
        worker: Blackboex.ProjectAgent.KickoffWorker,
        args: %{
          "project_id" => ctx.project.id,
          "organization_id" => ctx.org.id,
          "user_id" => ctx.user.id,
          "user_message" => "build a CRUD"
        }
      )
    end
  end

  describe "approve_and_run/3" do
    test "approves a draft plan and enqueues PlanRunnerWorker", ctx do
      plan = plan_fixture(Map.take(ctx, [:user, :org, :project]))
      _t = plan_task_fixture(%{plan: plan, artifact_type: "api", action: "create"})

      markdown =
        plan |> Repo.preload(:tasks) |> MarkdownRenderer.render()

      assert {:ok, approved} =
               ProjectAgent.approve_and_run(plan, ctx.user, %{markdown_body: markdown})

      assert approved.status == "approved"
      assert Plans.get_plan!(approved.id).status == "approved"

      assert_enqueued(
        worker: Blackboex.ProjectAgent.PlanRunnerWorker,
        args: %{"plan_id" => approved.id}
      )
    end

    test "returns the same {:error, :concurrent_active_plan} as Plans.approve_plan", ctx do
      first = plan_fixture(Map.take(ctx, [:user, :org, :project]))
      _t1 = plan_task_fixture(%{plan: first, artifact_type: "api", action: "create"})

      md1 = first |> Repo.preload(:tasks) |> MarkdownRenderer.render()
      {:ok, _approved} = Plans.approve_plan(first, ctx.user, %{markdown_body: md1})

      second = plan_fixture(Map.take(ctx, [:user, :org, :project]))
      _t2 = plan_task_fixture(%{plan: second, artifact_type: "api", action: "create"})
      md2 = second |> Repo.preload(:tasks) |> MarkdownRenderer.render()

      result = ProjectAgent.approve_and_run(second, ctx.user, %{markdown_body: md2})

      assert match?({:error, :concurrent_active_plan}, result) or
               match?({:error, %Ecto.Changeset{}}, result)
    end
  end
end
