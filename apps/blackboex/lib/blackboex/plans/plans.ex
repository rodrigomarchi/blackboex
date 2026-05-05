defmodule Blackboex.Plans.Plans do
  @moduledoc """
  Sub-context implementing the `Plan` state machine, plan/task transitions,
  the concurrent-approve race (`{:error, :concurrent_active_plan}`), and
  `start_continuation/2` (re-plan from a `:partial`/`:failed` parent).

  External callers use `Blackboex.Plans` (the facade); this module is the
  implementation. Query composition lives in
  `Blackboex.Plans.PlanQueries`.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Plans.MarkdownParser
  alias Blackboex.Plans.Plan
  alias Blackboex.Plans.PlanQueries
  alias Blackboex.Plans.PlanTask
  alias Blackboex.Repo

  @terminal_statuses ~w(done partial failed)
  @uniq_active_idx "plans_one_active_per_project_idx"

  @type violation :: MarkdownParser.violation()
  @type plan_error ::
          :concurrent_active_plan
          | :already_terminal
          | :parent_still_active
          | :invalid_markdown_edit
          | {:invalid_markdown_edit, [violation()]}
          | Ecto.Changeset.t()

  # ── Query helpers ──────────────────────────────────────────────

  @spec list_plans_for_project(Ecto.UUID.t(), keyword()) :: [Plan.t()]
  def list_plans_for_project(project_id, opts \\ []) do
    project_id
    |> PlanQueries.for_project(opts)
    |> Repo.all()
  end

  @spec get_plan!(Ecto.UUID.t()) :: Plan.t()
  def get_plan!(id), do: Repo.get!(Plan, id)

  @spec get_active_plan(Ecto.UUID.t()) :: Plan.t() | nil
  def get_active_plan(project_id) do
    project_id
    |> PlanQueries.active_for_project()
    |> Repo.one()
  end

  @spec list_tasks(Plan.t()) :: [PlanTask.t()]
  def list_tasks(%Plan{id: id}) do
    id
    |> PlanQueries.tasks_for_plan()
    |> Repo.all()
  end

  @spec get_task!(Ecto.UUID.t()) :: PlanTask.t()
  def get_task!(id), do: Repo.get!(PlanTask, id)

  @spec list_running_tasks() :: [PlanTask.t()]
  def list_running_tasks do
    PlanQueries.running_tasks_with_child_run_id()
    |> Repo.all()
  end

  # ── Plan creation ─────────────────────────────────────────────

  @spec create_draft_plan(
          Blackboex.Projects.Project.t(),
          Blackboex.Accounts.User.t(),
          %{
            user_message: String.t(),
            tasks: [map()],
            title: String.t(),
            markdown_body: String.t()
          }
        ) :: {:ok, Plan.t()} | {:error, plan_error()}
  def create_draft_plan(project, _user, %{tasks: tasks} = attrs) when is_list(tasks) do
    plan_attrs = %{
      project_id: project.id,
      status: "draft",
      title: Map.fetch!(attrs, :title),
      user_message: Map.fetch!(attrs, :user_message),
      markdown_body: Map.fetch!(attrs, :markdown_body),
      run_id: Map.get(attrs, :run_id),
      parent_plan_id: Map.get(attrs, :parent_plan_id),
      model_tier_caps: Map.get(attrs, :model_tier_caps, %{})
    }

    Repo.transaction(fn ->
      with {:ok, plan} <- insert_plan(plan_attrs),
           {:ok, _} <- insert_tasks(plan, tasks) do
        Repo.preload(plan, :tasks)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_plan(attrs) do
    %Plan{}
    |> Plan.changeset(attrs)
    |> Repo.insert()
  end

  defp insert_tasks(_plan, []), do: {:ok, []}

  defp insert_tasks(plan, tasks) do
    tasks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {raw, idx}, {:ok, acc} ->
      attrs =
        raw
        |> Map.new()
        |> Map.put(:plan_id, plan.id)
        |> Map.put_new(:order, idx)
        |> Map.put_new(:status, "pending")

      case %PlanTask{} |> PlanTask.changeset(attrs) |> Repo.insert() do
        {:ok, task} -> {:cont, {:ok, [task | acc]}}
        {:error, cs} -> {:halt, {:error, cs}}
      end
    end)
  end

  # ── Approval ──────────────────────────────────────────────────

  @spec approve_plan(Plan.t(), Blackboex.Accounts.User.t(), %{markdown_body: String.t()}) ::
          {:ok, Plan.t()} | {:error, plan_error()}
  def approve_plan(%Plan{} = plan, user, %{markdown_body: markdown}) when is_binary(markdown) do
    plan = Repo.preload(plan, :tasks)

    cond do
      plan.status in @terminal_statuses ->
        {:error, :already_terminal}

      plan.status != "draft" ->
        {:error, :already_terminal}

      true ->
        with {:ok, parsed} <- MarkdownParser.parse_and_validate(markdown, plan) do
          do_approve(plan, user, markdown, parsed)
        else
          {:error, violations} when is_list(violations) ->
            {:error, {:invalid_markdown_edit, violations}}
        end
    end
  end

  defp do_approve(plan, user, markdown, parsed) do
    Repo.transaction(fn ->
      _ = sync_tasks_from_parsed(plan, parsed.tasks)

      cs =
        Plan.status_changeset(plan, %{
          status: "approved",
          approved_by_user_id: user.id,
          approved_at: DateTime.utc_now()
        })
        |> Ecto.Changeset.put_change(:markdown_body, markdown)
        |> Ecto.Changeset.put_change(:title, parsed.title)

      case Repo.update(cs) do
        {:ok, approved} -> Repo.preload(approved, :tasks)
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
    |> translate_active_constraint()
  end

  # When the partial-unique index trips, Ecto's `unique_constraint/3` turns
  # the violation into a changeset error keyed on `:project_id`. Translate
  # that to the structured `{:error, :concurrent_active_plan}` tuple.
  defp translate_active_constraint({:ok, _} = ok), do: ok

  defp translate_active_constraint({:error, %Ecto.Changeset{} = cs}) do
    if active_constraint_error?(cs.errors) do
      {:error, :concurrent_active_plan}
    else
      {:error, cs}
    end
  end

  defp translate_active_constraint(other), do: other

  defp active_constraint_error?(errors) do
    Enum.any?(errors, fn
      {:project_id, {_msg, opts}} ->
        Keyword.get(opts, :constraint) == :unique and
          Keyword.get(opts, :constraint_name) == @uniq_active_idx

      _ ->
        false
    end)
  end

  # `Repo.transaction` re-raises Ecto.ConstraintError out of the lambda when
  # not handled by a changeset — at the outer level we rescue and translate.
  defp wrap_constraint_call(fun) do
    fun.()
  rescue
    e in Ecto.ConstraintError ->
      if e.constraint == @uniq_active_idx do
        {:error, :concurrent_active_plan}
      else
        reraise e, __STACKTRACE__
      end
  end

  defp sync_tasks_from_parsed(%Plan{tasks: existing}, parsed_tasks)
       when is_list(existing) and is_list(parsed_tasks) do
    by_order = Map.new(existing, fn t -> {t.order, t} end)

    Enum.each(parsed_tasks, fn parsed ->
      case Map.get(by_order, parsed.order) do
        nil ->
          # Free-form reorder (or extra task in markdown). v1 ignores extras
          # since the planner authoritatively defines task structure; only
          # textual fields on existing rows are merged.
          :ok

        existing_task ->
          existing_task
          |> PlanTask.changeset(%{
            title: parsed.title,
            params: parsed.params,
            acceptance_criteria: parsed.acceptance_criteria
          })
          |> Repo.update()
      end
    end)
  end

  # Public-via-facade approve with the constraint rescue wired in.
  @spec approve_plan_with_race_guard(Plan.t(), Blackboex.Accounts.User.t(), %{
          markdown_body: String.t()
        }) ::
          {:ok, Plan.t()} | {:error, plan_error()}
  def approve_plan_with_race_guard(plan, user, attrs) do
    wrap_constraint_call(fn -> approve_plan(plan, user, attrs) end)
  end

  # ── Plan transitions (state machine) ───────────────────────────

  @spec mark_plan_running(Plan.t()) :: {:ok, Plan.t()} | {:error, plan_error()}
  def mark_plan_running(%Plan{status: "approved"} = plan) do
    plan
    |> Plan.status_changeset(%{status: "running"})
    |> Repo.update()
  end

  def mark_plan_running(%Plan{status: status}) when status in @terminal_statuses,
    do: {:error, :already_terminal}

  def mark_plan_running(%Plan{}), do: {:error, :already_terminal}

  @spec mark_plan_done(Plan.t()) :: {:ok, Plan.t()} | {:error, plan_error()}
  def mark_plan_done(%Plan{status: "running"} = plan) do
    plan
    |> Plan.status_changeset(%{status: "done"})
    |> Repo.update()
  end

  def mark_plan_done(%Plan{}), do: {:error, :already_terminal}

  @spec mark_plan_partial(Plan.t(), String.t()) :: {:ok, Plan.t()} | {:error, plan_error()}
  def mark_plan_partial(%Plan{status: "running"} = plan, reason) when is_binary(reason) do
    plan
    |> Plan.status_changeset(%{status: "partial", failure_reason: reason})
    |> Repo.update()
  end

  def mark_plan_partial(%Plan{}, _reason), do: {:error, :already_terminal}

  @spec mark_plan_failed(Plan.t(), String.t()) :: {:ok, Plan.t()} | {:error, plan_error()}
  def mark_plan_failed(%Plan{status: status} = plan, reason)
      when status in ~w(running approved) and is_binary(reason) do
    plan
    |> Plan.status_changeset(%{status: "failed", failure_reason: reason})
    |> Repo.update()
  end

  def mark_plan_failed(%Plan{}, _reason), do: {:error, :already_terminal}

  # ── Task transitions ──────────────────────────────────────────

  @spec mark_task_running(PlanTask.t(), Ecto.UUID.t()) ::
          {:ok, PlanTask.t()} | {:error, Ecto.Changeset.t()}
  def mark_task_running(%PlanTask{} = task, child_run_id) when is_binary(child_run_id) do
    task
    |> PlanTask.changeset(%{
      status: "running",
      child_run_id: child_run_id,
      started_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @spec mark_task_done(PlanTask.t()) :: {:ok, PlanTask.t()} | {:error, Ecto.Changeset.t()}
  def mark_task_done(%PlanTask{} = task) do
    task
    |> PlanTask.changeset(%{status: "done", finished_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @spec mark_task_failed(PlanTask.t(), String.t()) ::
          {:ok, PlanTask.t()} | {:error, Ecto.Changeset.t()}
  def mark_task_failed(%PlanTask{} = task, reason) when is_binary(reason) do
    task
    |> PlanTask.changeset(%{
      status: "failed",
      error_message: reason,
      finished_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  # ── Re-plan: start_continuation/2 ──────────────────────────────

  @spec start_continuation(Plan.t(), Blackboex.Accounts.User.t()) ::
          {:ok, Plan.t()} | {:error, plan_error()}
  def start_continuation(%Plan{status: status}, _user)
      when status not in ~w(partial failed) do
    {:error, :parent_still_active}
  end

  def start_continuation(%Plan{} = parent, _user) do
    parent = Repo.preload(parent, :tasks)
    done_tasks = Enum.filter(parent.tasks, &(&1.status == "done"))

    Repo.transaction(fn -> do_start_continuation(parent, done_tasks) end)
  end

  defp do_start_continuation(parent, done_tasks) do
    case insert_plan(continuation_attrs(parent)) do
      {:ok, child} ->
        copy_done_tasks(child.id, done_tasks)
        Repo.preload(child, :tasks)

      {:error, cs} ->
        Repo.rollback(cs)
    end
  end

  defp continuation_attrs(parent) do
    %{
      project_id: parent.project_id,
      status: "draft",
      title: parent.title,
      user_message: parent.user_message,
      markdown_body: parent.markdown_body,
      parent_plan_id: parent.id,
      model_tier_caps: parent.model_tier_caps
    }
  end

  defp copy_done_tasks(child_id, done_tasks) do
    done_tasks
    |> Enum.with_index()
    |> Enum.each(fn {t, idx} -> insert_skipped_task(child_id, t, idx) end)
  end

  defp insert_skipped_task(child_id, t, idx) do
    attrs = %{
      plan_id: child_id,
      order: idx,
      artifact_type: t.artifact_type,
      action: t.action,
      target_artifact_id: t.target_artifact_id,
      title: t.title,
      params: t.params,
      acceptance_criteria: t.acceptance_criteria,
      status: "skipped"
    }

    {:ok, _} = %PlanTask{} |> PlanTask.changeset(attrs) |> Repo.insert()
  end

  # ── Continuation: append Planner-produced :pending tasks ──────

  @spec add_planner_tasks_to_continuation(Plan.t(), [map()]) ::
          {:ok, Plan.t()} | {:error, :not_draft | Ecto.Changeset.t()}
  def add_planner_tasks_to_continuation(%Plan{status: "draft"} = plan, []) do
    {:ok, Repo.preload(plan, :tasks, force: true)}
  end

  def add_planner_tasks_to_continuation(%Plan{status: "draft"} = plan, tasks)
      when is_list(tasks) do
    plan = Repo.preload(plan, :tasks, force: true)
    next_order = next_task_order(plan)

    Repo.transaction(fn ->
      case insert_continuation_tasks(plan, tasks, next_order) do
        {:ok, _} -> Repo.preload(plan, :tasks, force: true)
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  def add_planner_tasks_to_continuation(%Plan{}, _tasks), do: {:error, :not_draft}

  @spec insert_continuation_tasks(Plan.t(), [map()], non_neg_integer()) ::
          {:ok, [PlanTask.t()]} | {:error, Ecto.Changeset.t()}
  defp insert_continuation_tasks(%Plan{} = plan, tasks, next_order) do
    tasks
    |> Enum.with_index(next_order)
    |> Enum.reduce_while({:ok, []}, fn {raw, idx}, {:ok, acc} ->
      attrs = continuation_task_attrs(plan, raw, idx)

      case %PlanTask{} |> PlanTask.changeset(attrs) |> Repo.insert() do
        {:ok, task} -> {:cont, {:ok, [task | acc]}}
        {:error, cs} -> {:halt, {:error, cs}}
      end
    end)
  end

  @spec continuation_task_attrs(Plan.t(), map(), non_neg_integer()) :: map()
  defp continuation_task_attrs(%Plan{id: plan_id}, raw, idx) do
    raw
    |> Map.new()
    |> Map.put(:plan_id, plan_id)
    |> Map.put(:order, idx)
    |> Map.put(:status, "pending")
  end

  defp next_task_order(%Plan{tasks: tasks}) when is_list(tasks) do
    case tasks do
      [] -> 0
      [_ | _] -> (tasks |> Enum.map(& &1.order) |> Enum.max()) + 1
    end
  end
end
