defmodule Blackboex.ProjectAgent.PlanRunnerWorker do
  @moduledoc ~S"""
  Callback-driven Oban worker that advances a `Plan` one task at a time.

  Lifecycle (each call to `perform/1`):

    1. Load the plan + tasks.
    2. If any task is `:running`, exit — `RecoveryWorker` polls every 30s and
       calls `BroadcastAdapter.handle_terminal/4` when the child run reaches a
       terminal state.
    3. Otherwise, find the next `:pending` task in `:order`.
    4. If there is none → `finalize_plan/2` (`:done` if all `:done`/`:skipped`,
       else `:partial` with the first failure reason).
    5. Otherwise →
       a. Pre-generate a `child_run_id` UUID.
       b. Enqueue the matching per-artifact `KickoffWorker` with
          `%{"run_id" => child_run_id, ...}` so the worker uses the pre-known
          run id when creating its DB row.
       c. Mark the `PlanTask` `:running` with `child_run_id` so the
          `RecoveryWorker` can poll `*Conversations.get_run!/1` against it.
       d. Touch the planner Run heartbeat and exit.

  **No PubSub subscription is made from this worker.** Advancement is driven
  by `Blackboex.ProjectAgent.RecoveryWorker` (poll-based, every 30s), which
  calls `BroadcastAdapter.handle_terminal/4` when it detects the child Run is
  in a terminal state. This is option (b) from the M5 decision — simpler than
  a per-task GenServer listener and crash-safe under Oban retries.
  """

  use Oban.Worker, queue: :project_orchestration, max_attempts: 3

  require Logger

  alias Blackboex.Agent.KickoffWorker, as: AgentKickoffWorker
  alias Blackboex.Agent.Pipeline.Budget
  alias Blackboex.Apis
  alias Blackboex.FlowAgent.KickoffWorker, as: FlowKickoffWorker
  alias Blackboex.Flows
  alias Blackboex.PageAgent.KickoffWorker, as: PageKickoffWorker
  alias Blackboex.Pages
  alias Blackboex.Plans
  alias Blackboex.Plans.{Plan, PlanTask}
  alias Blackboex.PlaygroundAgent.KickoffWorker, as: PlaygroundKickoffWorker
  alias Blackboex.Playgrounds
  alias Blackboex.ProjectConversations
  alias Blackboex.Projects.Project
  alias Blackboex.Repo

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"plan_id" => plan_id}}) do
    plan = Plans.get_plan!(plan_id) |> ensure_running()
    tasks = Plans.list_tasks(plan)

    cond do
      already_running_task?(tasks) ->
        :ok

      next_pending(tasks) == nil ->
        finalize_plan(plan, tasks)
        :ok

      true ->
        dispatch_next(plan, next_pending(tasks))
    end
  end

  # ── Helpers ────────────────────────────────────────────────────

  @spec ensure_running(Plan.t()) :: Plan.t()
  defp ensure_running(%Plan{status: "approved"} = plan) do
    case Plans.mark_plan_running(plan) do
      {:ok, running} -> running
      {:error, _} -> plan
    end
  end

  defp ensure_running(plan), do: plan

  @spec already_running_task?([PlanTask.t()]) :: boolean()
  defp already_running_task?(tasks), do: Enum.any?(tasks, &(&1.status == "running"))

  @spec next_pending([PlanTask.t()]) :: PlanTask.t() | nil
  defp next_pending(tasks) do
    tasks
    |> Enum.filter(&(&1.status == "pending"))
    |> Enum.sort_by(& &1.order)
    |> List.first()
  end

  @spec finalize_plan(Plan.t(), [PlanTask.t()]) :: :ok
  defp finalize_plan(plan, tasks) do
    cond do
      Enum.all?(tasks, &(&1.status in ~w(done skipped))) ->
        _ = Plans.mark_plan_done(plan)
        _ = append_terminal_event(plan, "completed", "Plan completed", %{})
        broadcast_plan_status_changed(plan, :done, nil)
        :ok

      Enum.any?(tasks, &(&1.status == "failed")) ->
        reason = first_failure_reason(tasks)
        _ = Plans.mark_plan_partial(plan, reason)

        _ =
          append_terminal_event(plan, "failed", "Plan halted: #{reason}", %{
            "reason" => reason,
            "plan_status" => "partial"
          })

        broadcast_plan_status_changed(plan, :partial, reason)
        :ok

      true ->
        :ok
    end
  end

  @spec append_terminal_event(Plan.t(), String.t(), String.t(), map()) :: :ok
  defp append_terminal_event(%Plan{run_id: nil}, _type, _content, _meta), do: :ok

  defp append_terminal_event(%Plan{run_id: run_id}, event_type, content, metadata) do
    case Blackboex.ProjectConversations.get_run(run_id) do
      nil ->
        :ok

      run ->
        _ =
          Blackboex.ProjectConversations.append_event(run, %{
            event_type: event_type,
            content: content,
            metadata: metadata
          })

        :ok
    end
  end

  @spec broadcast_plan_status_changed(
          Plan.t(),
          :done | :partial | :failed | :running,
          String.t() | nil
        ) :: :ok
  defp broadcast_plan_status_changed(%Plan{id: plan_id}, status, reason) do
    payload = %{plan_id: plan_id, status: status, reason: reason}

    _ =
      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "project_plan:#{plan_id}",
        {:plan_status_changed, payload}
      )

    :ok
  end

  @spec broadcast_task_dispatched(Plan.t(), PlanTask.t()) :: :ok
  defp broadcast_task_dispatched(%Plan{id: plan_id}, %PlanTask{} = task) do
    payload = %{
      plan_id: plan_id,
      task_id: task.id,
      task_order: task.order,
      artifact_type: task.artifact_type,
      action: task.action,
      title: task.title
    }

    _ =
      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "project_plan:#{plan_id}",
        {:project_task_dispatched, payload}
      )

    :ok
  end

  @spec first_failure_reason([PlanTask.t()]) :: String.t()
  defp first_failure_reason(tasks) do
    case Enum.find(tasks, &(&1.status == "failed")) do
      nil -> "task failed"
      %PlanTask{error_message: msg} when is_binary(msg) and msg != "" -> msg
      _ -> "task failed"
    end
  end

  @spec dispatch_next(Plan.t(), PlanTask.t()) :: :ok | {:error, term()}
  defp dispatch_next(plan, task) do
    with {:ok, child_run_id} <- enqueue_child(plan, task),
         {:ok, _running_task} <- Plans.mark_task_running(task, child_run_id) do
      _ = Budget.touch_run(plan.run_id)

      _ =
        append_terminal_event(
          plan,
          "task_dispatched",
          "Working on: #{task.title}",
          %{
            "task_id" => task.id,
            "task_order" => task.order,
            "artifact_type" => task.artifact_type,
            "action" => task.action
          }
        )

      _ = broadcast_task_dispatched(plan, task)
      :ok
    else
      {:error, reason} ->
        Logger.warning(
          "PlanRunnerWorker: failed to dispatch task #{task.id} (#{task.artifact_type}/#{task.action}): #{inspect(reason)}"
        )

        _ = Plans.mark_task_failed(task, "dispatch_failed: #{inspect(reason)}")
        # Re-enqueue ourselves so finalize_plan/2 fires next pass.
        _ = Oban.insert(__MODULE__.new(%{"plan_id" => plan.id}))
        :ok
    end
  end

  # ── Real dispatch ──────────────────────────────────────────────
  #
  # Dispatches the matching per-artifact KickoffWorker.
  # Strategy:
  #   1. Pre-generate a child_run_id UUID.
  #   2. Build KickoffWorker args that include `run_id: child_run_id`.
  #   3. Insert the Oban job via `Oban.insert!/2`.
  #
  # The child KickoffWorker uses the pre-supplied run_id when creating its DB
  # Run row (see each worker's `perform/1` — they accept an optional "run_id"
  # arg and use it as `%RunStruct{id: run_id}` before `Repo.insert`). This
  # guarantees `task.child_run_id` matches the actual DB row that the
  # RecoveryWorker queries via `*Conversations.get_run!/1`.
  @spec enqueue_child(Plan.t(), PlanTask.t()) :: {:ok, Ecto.UUID.t()} | {:error, term()}
  defp enqueue_child(plan, %PlanTask{} = task) do
    child_run_id = Ecto.UUID.generate()

    with {:ok, ctx} <- load_dispatch_context(plan),
         {:ok, _job} <- do_enqueue(task, child_run_id, ctx) do
      {:ok, child_run_id}
    end
  end

  # Loads org/user context needed to build child worker args.
  # Primary source: the plan's ProjectRun (has organization_id + user_id).
  # Fallback: load the Project row for organization_id; use plan.approved_by_user_id for user_id.
  @spec load_dispatch_context(Plan.t()) ::
          {:ok,
           %{organization_id: String.t() | nil, user_id: integer() | nil, project_id: String.t()}}
          | {:error, term()}
  defp load_dispatch_context(%Plan{
         run_id: nil,
         project_id: project_id,
         approved_by_user_id: approver_id
       }) do
    org_id = org_id_from_project(project_id)
    {:ok, %{organization_id: org_id, user_id: approver_id, project_id: project_id}}
  end

  defp load_dispatch_context(%Plan{
         run_id: run_id,
         project_id: project_id,
         approved_by_user_id: approver_id
       }) do
    case ProjectConversations.get_run(run_id) do
      nil ->
        {:ok,
         %{
           organization_id: org_id_from_project(project_id),
           user_id: approver_id,
           project_id: project_id
         }}

      run ->
        {:ok,
         %{
           organization_id: run.organization_id,
           user_id: run.user_id,
           project_id: project_id
         }}
    end
  end

  @spec do_enqueue(PlanTask.t(), Ecto.UUID.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  defp do_enqueue(
         %PlanTask{
           artifact_type: "api",
           action: action,
           target_artifact_id: artifact_id,
           title: title
         } = task,
         child_run_id,
         ctx
       ) do
    # Agent.KickoffWorker uses "generation" (not "generate") for create runs.
    run_type = if action == "edit", do: "edit", else: "generation"
    trigger = build_trigger(task)

    with {:ok, api_id} <- resolve_artifact_id(:api, artifact_id, action, title, ctx) do
      args = %{
        "api_id" => api_id,
        "organization_id" => ctx.organization_id,
        "project_id" => ctx.project_id,
        "user_id" => ctx.user_id,
        "run_type" => run_type,
        "trigger_message" => trigger,
        "run_id" => child_run_id
      }

      {:ok, Oban.insert!(AgentKickoffWorker.new(args))}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp do_enqueue(
         %PlanTask{
           artifact_type: "flow",
           action: action,
           target_artifact_id: artifact_id,
           title: title
         } = task,
         child_run_id,
         ctx
       ) do
    run_type = if action == "edit", do: "edit", else: "generate"
    trigger = build_trigger(task)

    with {:ok, flow_id} <- resolve_artifact_id(:flow, artifact_id, action, title, ctx) do
      args = %{
        "flow_id" => flow_id,
        "organization_id" => ctx.organization_id,
        "project_id" => ctx.project_id,
        "user_id" => ctx.user_id,
        "run_type" => run_type,
        "trigger_message" => trigger,
        "run_id" => child_run_id
      }

      {:ok, Oban.insert!(FlowKickoffWorker.new(args))}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp do_enqueue(
         %PlanTask{
           artifact_type: "page",
           action: action,
           target_artifact_id: artifact_id,
           params: params,
           title: title
         } = task,
         child_run_id,
         ctx
       ) do
    org_id = Map.get(params || %{}, "organization_id") || ctx.organization_id
    run_type = if action == "edit", do: "edit", else: "generate"
    trigger = build_trigger(task)

    with {:ok, page_id} <-
           resolve_artifact_id(:page, artifact_id, action, title, %{ctx | organization_id: org_id}) do
      args = %{
        "page_id" => page_id,
        "organization_id" => org_id,
        "project_id" => ctx.project_id,
        "user_id" => ctx.user_id,
        "run_type" => run_type,
        "trigger_message" => trigger,
        "run_id" => child_run_id
      }

      {:ok, Oban.insert!(PageKickoffWorker.new(args))}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp do_enqueue(
         %PlanTask{
           artifact_type: "playground",
           action: action,
           target_artifact_id: artifact_id,
           title: title
         } = task,
         child_run_id,
         ctx
       ) do
    run_type = if action == "edit", do: "edit", else: "generate"
    trigger = build_trigger(task)

    with {:ok, playground_id} <- resolve_artifact_id(:playground, artifact_id, action, title, ctx) do
      args = %{
        "playground_id" => playground_id,
        "organization_id" => ctx.organization_id,
        "project_id" => ctx.project_id,
        "user_id" => ctx.user_id,
        "run_type" => run_type,
        "trigger_message" => trigger,
        "run_id" => child_run_id
      }

      {:ok, Oban.insert!(PlaygroundKickoffWorker.new(args))}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp do_enqueue(%PlanTask{artifact_type: type, action: action}, _run_id, _ctx) do
    {:error, {:unsupported_artifact_type, type, action}}
  end

  # ── Artifact resolution for :create tasks ─────────────────────
  #
  # For :edit tasks, the artifact must already exist (target_artifact_id is set).
  # For :create tasks, target_artifact_id is nil — we create the artifact now
  # so the child KickoffWorker has a real ID to work with.
  @spec resolve_artifact_id(atom(), Ecto.UUID.t() | nil, String.t(), String.t(), map()) ::
          {:ok, Ecto.UUID.t()} | {:error, term()}
  defp resolve_artifact_id(_type, id, _action, _title, _ctx) when is_binary(id), do: {:ok, id}

  defp resolve_artifact_id(:api, nil, "create", title, ctx) do
    case Apis.create_api(%{
           name: title,
           organization_id: ctx.organization_id,
           project_id: ctx.project_id,
           user_id: ctx.user_id
         }) do
      {:ok, api} -> {:ok, api.id}
      {:error, reason} -> {:error, {:create_api_failed, reason}}
    end
  end

  defp resolve_artifact_id(:flow, nil, "create", title, ctx) do
    case Flows.create_flow(%{
           name: title,
           organization_id: ctx.organization_id,
           project_id: ctx.project_id
         }) do
      {:ok, flow} -> {:ok, flow.id}
      {:error, reason} -> {:error, {:create_flow_failed, reason}}
    end
  end

  defp resolve_artifact_id(:page, nil, "create", title, ctx) do
    case Pages.create_page(%{
           title: title,
           organization_id: ctx.organization_id,
           project_id: ctx.project_id,
           user_id: ctx.user_id
         }) do
      {:ok, page} -> {:ok, page.id}
      {:error, reason} -> {:error, {:create_page_failed, reason}}
    end
  end

  defp resolve_artifact_id(:playground, nil, "create", title, ctx) do
    case Playgrounds.create_playground(%{
           name: title,
           organization_id: ctx.organization_id,
           project_id: ctx.project_id,
           user_id: ctx.user_id
         }) do
      {:ok, playground} -> {:ok, playground.id}
      {:error, reason} -> {:error, {:create_playground_failed, reason}}
    end
  end

  defp resolve_artifact_id(type, nil, action, _title, _ctx) do
    {:error, {:missing_artifact_id, type, action}}
  end

  @spec org_id_from_project(Ecto.UUID.t()) :: String.t() | nil
  defp org_id_from_project(project_id) do
    case Repo.get(Project, project_id) do
      nil -> nil
      project -> project.organization_id
    end
  end

  # The trigger_message is consumed by per-artifact agents as the natural-language
  # description of what to build. We pack the task's title plus its
  # acceptance_criteria so the artifact agent has the same spec the Planner
  # produced — without these, the agent only sees a generic placeholder.
  @spec build_trigger(PlanTask.t()) :: String.t()
  defp build_trigger(%PlanTask{title: title, acceptance_criteria: criteria, params: params}) do
    override =
      params
      |> case do
        m when is_map(m) -> Map.get(m, "trigger_message") || Map.get(m, :trigger_message)
        _ -> nil
      end

    case override do
      msg when is_binary(msg) and msg != "" ->
        msg

      _ ->
        criteria_block =
          (criteria || [])
          |> Enum.map(&"- #{&1}")
          |> Enum.join("\n")

        cond do
          is_binary(title) and title != "" and criteria_block != "" ->
            "#{title}\n\nAcceptance criteria:\n#{criteria_block}"

          is_binary(title) and title != "" ->
            title

          true ->
            "Project Agent automated task"
        end
    end
  end
end
