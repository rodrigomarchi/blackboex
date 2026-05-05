defmodule Blackboex.ProjectAgent.KickoffWorkerContinuationTest do
  @moduledoc """
  Continuation-mode tests for `Blackboex.ProjectAgent.KickoffWorker`.

  In continuation mode the worker:
    1. Receives a `parent_plan_id` and a draft `plan_id` (already created
       by `Plans.start_continuation/2` with parent's `:done` tasks copied
       as `:skipped`).
    2. Builds a prior-partial-summary from the parent plan and calls
       `Planner.build_plan/2` with `:prior_partial_summary`.
    3. Appends the new `:pending` tasks via
       `Plans.add_planner_tasks_to_continuation/2`.
    4. Broadcasts `{:plan_drafted, plan}` on the same project + plan
       topics as the initial-kickoff path so the LV picks the new draft
       up unchanged.
  """

  use Blackboex.DataCase, async: false
  use Oban.Testing, repo: Blackboex.Repo

  alias Blackboex.Plans
  alias Blackboex.ProjectAgent.KickoffWorker

  setup [:create_user_and_org, :create_project]

  setup do
    received = self()

    Application.put_env(:blackboex, :project_planner_client, fn _project, prompt ->
      send(received, {:planner_prompt, prompt})

      {:ok,
       %{
         title: "Continuation plan",
         tasks: [
           %{
             artifact_type: "page",
             action: "create",
             title: "Continuation page",
             params: %{},
             acceptance_criteria: ["page renders"]
           }
         ]
       }}
    end)

    on_exit(fn -> Application.delete_env(:blackboex, :project_planner_client) end)
    :ok
  end

  describe "perform/1 — continuation mode" do
    test "builds prior summary, appends :pending tasks, broadcasts :plan_drafted",
         %{user: user, project: project, org: org} do
      parent = partial_plan_fixture(%{project: project})
      {:ok, draft} = Plans.start_continuation(parent, user)

      Phoenix.PubSub.subscribe(Blackboex.PubSub, "project_plan:#{draft.id}")
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "project_plan:project:#{project.id}")

      args = %{
        "project_id" => project.id,
        "organization_id" => org.id,
        "user_id" => user.id,
        "user_message" => parent.user_message,
        "continuation" => true,
        "parent_plan_id" => parent.id,
        "plan_id" => draft.id
      }

      :ok = perform_job(KickoffWorker, args)

      # Planner was called and saw the prior summary
      assert_receive {:planner_prompt, prompt}

      volatile =
        prompt.messages
        |> Enum.reject(&Map.has_key?(&1, :cache_control))
        |> Enum.map(& &1.text)
        |> Enum.join("\n")

      assert volatile =~ "Prior plan summary"

      # New :pending tasks appended
      tasks = Plans.list_tasks(draft)
      pending = Enum.filter(tasks, &(&1.status == "pending"))
      skipped = Enum.filter(tasks, &(&1.status == "skipped"))
      assert skipped != []
      assert length(pending) == 1
      assert hd(pending).title == "Continuation page"

      # Broadcast carries the same draft plan id
      assert_receive {:plan_drafted, %{id: id, project_id: pid}}
      assert id == draft.id
      assert pid == project.id
    end

    test "leaves the parent plan unchanged",
         %{user: user, project: project, org: org} do
      parent = partial_plan_fixture(%{project: project})
      {:ok, draft} = Plans.start_continuation(parent, user)

      args = %{
        "project_id" => project.id,
        "organization_id" => org.id,
        "user_id" => user.id,
        "user_message" => parent.user_message,
        "continuation" => true,
        "parent_plan_id" => parent.id,
        "plan_id" => draft.id
      }

      :ok = perform_job(KickoffWorker, args)

      reloaded_parent = Plans.get_plan!(parent.id)
      assert reloaded_parent.status == "partial"
    end
  end
end
