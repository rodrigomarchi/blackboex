defmodule Blackboex.ProjectAgent.KickoffWorker do
  @moduledoc ~S"""
  Oban worker that opens a `ProjectConversation` + `ProjectRun` for the
  given project, calls `Blackboex.ProjectAgent.Planner.build_plan/2` to
  produce a typed plan, persists `Plan` + `PlanTask` rows in `:draft`,
  and broadcasts `{:plan_drafted, plan}` on `project_plan:#{plan.id}` and
  the project-scoped topic `project_plan:project:#{project_id}` (used by
  the LiveView before any `:plan` exists).

  Tier `:planner`. `max_attempts: 3`.
  """

  use Oban.Worker,
    queue: :project_orchestration,
    max_attempts: 3,
    unique: [keys: [:project_id], period: 30]

  require Logger

  alias Blackboex.Accounts.User
  alias Blackboex.Plans
  alias Blackboex.Plans.Plan
  alias Blackboex.Plans.PlanTask
  alias Blackboex.ProjectAgent.Planner
  alias Blackboex.ProjectConversations
  alias Blackboex.Projects
  alias Blackboex.Repo

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"continuation" => true} = args}) do
    perform_continuation(args)
  end

  def perform(%Oban.Job{args: args}) do
    %{
      "project_id" => project_id,
      "organization_id" => organization_id,
      "user_id" => user_id,
      "user_message" => user_message
    } = args

    with {:ok, project} <- fetch_project(organization_id, project_id),
         {:ok, user} <- fetch_user(user_id),
         {:ok, conversation} <- open_conversation(project, organization_id),
         {:ok, run} <-
           ensure_run(args, conversation, project, organization_id, user_id, user_message),
         {:ok, _event} <-
           ProjectConversations.append_event(run, %{
             event_type: "user_message",
             content: user_message
           }),
         {:ok, _running_run} <- ProjectConversations.mark_run_running(run),
         {:ok, %{plan_attrs: plan_attrs, task_attrs: task_attrs}} <-
           Planner.build_plan(project, %{user_message: user_message, run_id: run.id}),
         {:ok, plan} <-
           Plans.create_draft_plan(project, user, %{
             user_message: user_message,
             tasks: task_attrs,
             title: plan_attrs.title,
             markdown_body: plan_attrs.markdown_body
           }),
         {:ok, plan_with_run} <- link_plan_to_run(plan, run),
         {:ok, _drafted_event} <-
           ProjectConversations.append_event(run, %{
             event_type: "plan_drafted",
             content: plan_attrs.title,
             metadata: %{"plan_id" => plan.id, "tasks_count" => length(task_attrs)}
           }),
         {:ok, _completed_run} <-
           ProjectConversations.complete_run(run, %{status: "completed"}) do
      broadcast_plan_drafted(plan_with_run)
      :ok
    else
      {:error, reason} ->
        handle_failure(args, reason)
    end
  end

  # ── Continuation mode ─────────────────────────────────────────────
  #
  # Re-invoked by the LiveView "Continue from where you stopped" button
  # AFTER `Plans.start_continuation/2` has already created the draft Plan
  # with parent's `:done` tasks copied as `:skipped`. This worker is
  # responsible for building a prior-partial-summary from the parent,
  # calling the Planner with that summary, appending the produced
  # `:pending` tasks via `Plans.add_planner_tasks_to_continuation/2`, and
  # re-broadcasting `:plan_drafted` so the LV picks up the now-complete
  # draft.

  @spec perform_continuation(map()) :: :ok | {:error, term()}
  defp perform_continuation(args) do
    %{
      "project_id" => project_id,
      "organization_id" => organization_id,
      "user_message" => user_message,
      "parent_plan_id" => parent_plan_id,
      "plan_id" => plan_id
    } = args

    with {:ok, project} <- fetch_project(organization_id, project_id),
         {:ok, parent} <- fetch_plan(parent_plan_id),
         {:ok, draft} <- fetch_draft_plan(plan_id),
         summary = build_prior_partial_summary(parent),
         {:ok, %{task_attrs: task_attrs}} <-
           Planner.build_plan(project, %{
             user_message: user_message,
             run_id: draft.run_id,
             prior_partial_summary: summary
           }),
         {:ok, plan_with_tasks} <-
           Plans.add_planner_tasks_to_continuation(draft, task_attrs) do
      broadcast_plan_drafted(plan_with_tasks)
      :ok
    else
      {:error, reason} ->
        Logger.warning("ProjectAgent.KickoffWorker continuation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec fetch_plan(Ecto.UUID.t()) :: {:ok, Plan.t()} | {:error, :plan_not_found}
  defp fetch_plan(plan_id) do
    case Repo.get(Plan, plan_id) do
      nil -> {:error, :plan_not_found}
      plan -> {:ok, Repo.preload(plan, :tasks)}
    end
  end

  @spec fetch_draft_plan(Ecto.UUID.t()) ::
          {:ok, Plan.t()} | {:error, :plan_not_found | :not_draft}
  defp fetch_draft_plan(plan_id) do
    with {:ok, plan} <- fetch_plan(plan_id) do
      case plan.status do
        "draft" -> {:ok, plan}
        _ -> {:error, :not_draft}
      end
    end
  end

  @spec build_prior_partial_summary(Plan.t()) :: String.t()
  defp build_prior_partial_summary(%Plan{} = parent) do
    failure = parent.failure_reason || "no failure reason recorded"
    done = parent.tasks |> Enum.filter(&(&1.status == "done")) |> task_titles()
    failed = parent.tasks |> Enum.filter(&(&1.status == "failed")) |> task_titles()
    pending = parent.tasks |> Enum.filter(&(&1.status in ["pending", "running"])) |> task_titles()

    """
    Prior plan #{parent.id} ended with status #{parent.status}.
    Failure reason: #{failure}
    Completed tasks: #{done}
    Failed tasks: #{failed}
    Tasks not yet executed: #{pending}
    """
    |> String.trim_trailing()
  end

  @spec task_titles([PlanTask.t()]) :: String.t()
  defp task_titles([]), do: "(none)"

  defp task_titles(tasks) do
    tasks
    |> Enum.sort_by(& &1.order)
    |> Enum.map_join(", ", &"#{&1.order + 1}. #{&1.title}")
  end

  @spec link_plan_to_run(
          Blackboex.Plans.Plan.t(),
          Blackboex.ProjectConversations.ProjectRun.t()
        ) :: {:ok, Blackboex.Plans.Plan.t()} | {:error, Ecto.Changeset.t()}
  defp link_plan_to_run(plan, run) do
    plan
    |> Ecto.Changeset.change(%{run_id: run.id})
    |> Repo.update()
  end

  @spec fetch_project(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Blackboex.Projects.Project.t()} | {:error, :project_not_found}
  defp fetch_project(organization_id, project_id) do
    case Projects.get_project(organization_id, project_id) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  @spec fetch_user(integer() | String.t()) :: {:ok, User.t()} | {:error, :user_not_found}
  defp fetch_user(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  @spec open_conversation(Blackboex.Projects.Project.t(), Ecto.UUID.t()) ::
          {:ok, Blackboex.ProjectConversations.ProjectConversation.t()}
          | {:error, Ecto.Changeset.t()}
  defp open_conversation(project, organization_id) do
    ProjectConversations.get_or_create_active_conversation(project.id, organization_id)
  end

  @spec ensure_run(
          map(),
          Blackboex.ProjectConversations.ProjectConversation.t(),
          Blackboex.Projects.Project.t(),
          Ecto.UUID.t(),
          Ecto.UUID.t() | integer(),
          String.t()
        ) :: {:ok, Blackboex.ProjectConversations.ProjectRun.t()} | {:error, term()}
  defp ensure_run(
         %{"run_id" => run_id},
         _conversation,
         _project,
         _org_id,
         _user_id,
         _user_message
       )
       when is_binary(run_id) do
    case ProjectConversations.get_run(run_id) do
      nil -> {:error, :run_not_found}
      run -> {:ok, run}
    end
  end

  defp ensure_run(_args, conversation, project, organization_id, user_id, user_message) do
    ProjectConversations.create_run(%{
      conversation_id: conversation.id,
      project_id: project.id,
      organization_id: organization_id,
      user_id: user_id,
      run_type: "plan",
      status: "pending",
      trigger_message: user_message
    })
  end

  @spec handle_failure(map(), term()) :: {:error, term()}
  defp handle_failure(args, reason) do
    Logger.warning("ProjectAgent.KickoffWorker failed: #{inspect(reason)}")
    formatted = format_reason(reason)

    case ProjectConversations.get_active_conversation(args["project_id"]) do
      nil ->
        :ok

      conv ->
        case ProjectConversations.list_runs(conv.id) do
          [run | _] ->
            _ =
              ProjectConversations.append_event(run, %{
                event_type: "failed",
                content: friendly_failure_message(reason),
                metadata: %{"reason" => formatted}
              })

            _ = ProjectConversations.fail_run(run, formatted)
            :ok

          _ ->
            :ok
        end
    end

    broadcast_plan_failed(args["project_id"], reason, formatted)

    {:error, reason}
  end

  @spec broadcast_plan_failed(Ecto.UUID.t() | nil, term(), String.t()) :: :ok
  defp broadcast_plan_failed(nil, _reason, _formatted), do: :ok

  defp broadcast_plan_failed(project_id, reason, formatted) do
    payload = %{
      project_id: project_id,
      reason: reason,
      message: friendly_failure_message(reason),
      detail: formatted
    }

    _ =
      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "project_plan:project:#{project_id}",
        {:plan_failed, payload}
      )

    :ok
  end

  @spec friendly_failure_message(term()) :: String.t()
  defp friendly_failure_message(:planner_backend_not_configured),
    do: "Anthropic API key is not configured for this project — open LLM Integrations to add one."

  defp friendly_failure_message(:rate_limited),
    do: "Rate limit reached for the planner tier. Try again in a moment."

  defp friendly_failure_message(:project_not_found),
    do: "Project could not be found."

  defp friendly_failure_message(:user_not_found),
    do: "User session is invalid — please log in again."

  defp friendly_failure_message(:org_not_found),
    do: "Organization context is missing for this project."

  defp friendly_failure_message(reason) when is_binary(reason),
    do: "Planner failed: #{reason}"

  defp friendly_failure_message(reason),
    do: "Planner failed: #{inspect(reason)}"

  @spec format_reason(term()) :: String.t()
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  @spec broadcast_plan_drafted(Blackboex.Plans.Plan.t()) :: :ok
  defp broadcast_plan_drafted(plan) do
    payload = %{id: plan.id, project_id: plan.project_id, plan: plan}

    _ =
      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "project_plan:#{plan.id}",
        {:plan_drafted, payload}
      )

    _ =
      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "project_plan:project:#{plan.project_id}",
        {:plan_drafted, payload}
      )

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end
