defmodule Blackboex.ProjectAgent do
  @moduledoc """
  Public facade for the Project Agent: opens a `ProjectConversation` +
  `ProjectRun`, enqueues the `KickoffWorker` (which calls the `Planner`
  and persists a draft `Plan`), and exposes the approval entry point that
  enqueues the `PlanRunnerWorker` to execute the approved plan.

  External callers (web, workers) MUST use this facade — never reach into
  `Blackboex.ProjectAgent.{Planner, KickoffWorker, PlanRunnerWorker,
  BroadcastAdapter, ProjectIndex}` directly.
  """

  alias Blackboex.Accounts.User
  alias Blackboex.Plans
  alias Blackboex.Plans.Plan
  alias Blackboex.ProjectAgent.KickoffWorker
  alias Blackboex.ProjectAgent.PlanRunnerWorker
  alias Blackboex.ProjectConversations
  alias Blackboex.ProjectConversations.{ProjectConversation, ProjectRun}
  alias Blackboex.Projects.Project

  @doc """
  Opens a (or reuses the) `ProjectConversation` for the project, creates
  a new `ProjectRun` (`run_type: "plan"`), and enqueues the
  `KickoffWorker` which will call the planner.

  Returns `{:ok, conversation, run}` on success.
  """
  @spec start_planning(Project.t(), User.t(), String.t()) ::
          {:ok, ProjectConversation.t(), ProjectRun.t()} | {:error, term()}
  def start_planning(%Project{} = project, %User{} = user, user_message)
      when is_binary(user_message) do
    with {:ok, conversation} <-
           ProjectConversations.get_or_create_active_conversation(
             project.id,
             project.organization_id
           ),
         {:ok, run} <-
           ProjectConversations.create_run(%{
             conversation_id: conversation.id,
             project_id: project.id,
             organization_id: project.organization_id,
             user_id: user.id,
             run_type: "plan",
             status: "pending",
             trigger_message: user_message
           }),
         {:ok, _} <- enqueue_kickoff(project, user, user_message) do
      {:ok, conversation, run}
    end
  end

  @doc """
  Approves a `:draft` `Plan` (re-validating its possibly user-edited
  markdown body via `Plans.approve_plan/3`) and enqueues the
  `PlanRunnerWorker` to start executing it.

  Returns `{:ok, approved_plan}` on success or the same error tuples as
  `Plans.approve_plan/3` (notably `{:error, :concurrent_active_plan}`,
  `{:error, :already_terminal}`, `{:error, {:invalid_markdown_edit,
  violations}}`).
  """
  @spec approve_and_run(Plan.t(), User.t(), %{markdown_body: String.t()}) ::
          {:ok, Plan.t()} | {:error, term()}
  def approve_and_run(%Plan{} = plan, %User{} = user, %{markdown_body: _} = attrs) do
    with {:ok, approved} <- Plans.approve_plan(plan, user, attrs) do
      _ =
        %{"plan_id" => approved.id}
        |> PlanRunnerWorker.new()
        |> Oban.insert()

      {:ok, approved}
    end
  end

  @spec enqueue_kickoff(Project.t(), User.t(), String.t()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp enqueue_kickoff(project, user, user_message) do
    %{
      "project_id" => project.id,
      "organization_id" => project.organization_id,
      "user_id" => user.id,
      "user_message" => user_message
    }
    |> KickoffWorker.new()
    |> Oban.insert()
  end
end
