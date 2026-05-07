defmodule Blackboex.Plans do
  @moduledoc """
  Public facade for the project-level Plans context.

  Plans are typed, immutable-after-approval artifacts produced by the
  Project Agent. They drive the `PlanRunnerWorker` (M5) which dispatches
  each `PlanTask` to the matching per-artifact `KickoffWorker`.

  Lifecycle:

      draft → approved → running → done | partial | failed

  The DB enforces "at most one active plan per project" via the partial
  unique index `plans_one_active_per_project_idx` on
  `(project_id) WHERE status IN ('approved','running')`. Concurrent
  approvals are wrapped: the loser receives
  `{:error, :concurrent_active_plan}` instead of a raw constraint
  exception.

  Re-plan ("Continue from partial") creates a new draft `Plan` with
  `parent_plan_id` pointing at the parent. The parent's `:done` tasks are
  copied as `:skipped` rows on the child (creation-time-only — see
  `PlanTask`). The fresh draft requires its own approval (gate D2).
  """

  alias Blackboex.Plans.MarkdownParser
  alias Blackboex.Plans.Plans

  @type violation :: MarkdownParser.violation()
  @type plan_error ::
          :concurrent_active_plan
          | :already_terminal
          | :parent_still_active
          | :invalid_markdown_edit
          | {:invalid_markdown_edit, [violation()]}
          | Ecto.Changeset.t()

  # ── Plan lookups & lists ───────────────────────────────────────

  defdelegate list_plans_for_project(project_id, opts \\ []), to: Plans
  defdelegate list_plans_for_conversation(conversation_id, opts \\ []), to: Plans
  defdelegate get_plan!(id), to: Plans
  defdelegate get_active_plan(project_id), to: Plans
  defdelegate get_active_plan_for_conversation(conversation_id), to: Plans
  defdelegate list_tasks(plan), to: Plans
  defdelegate get_task!(id), to: Plans
  defdelegate list_running_tasks(), to: Plans

  # ── Plan transitions ──────────────────────────────────────────

  defdelegate create_draft_plan(project, user, attrs), to: Plans

  @doc """
  Approves a plan after re-validating the (possibly user-edited) markdown
  body against the plan's invariants.

  Wraps the partial-unique constraint as `{:error, :concurrent_active_plan}`
  when a sibling worker beats this transaction to the active slot.
  """
  @spec approve_plan(Blackboex.Plans.Plan.t(), Blackboex.Accounts.User.t(), %{
          markdown_body: String.t()
        }) ::
          {:ok, Blackboex.Plans.Plan.t()} | {:error, plan_error()}
  def approve_plan(plan, user, attrs), do: Plans.approve_plan_with_race_guard(plan, user, attrs)

  defdelegate mark_plan_running(plan), to: Plans
  defdelegate mark_plan_done(plan), to: Plans
  defdelegate mark_plan_partial(plan, reason), to: Plans
  defdelegate mark_plan_failed(plan, reason), to: Plans

  defdelegate start_continuation(parent, user), to: Plans
  defdelegate add_planner_tasks_to_continuation(plan, tasks), to: Plans

  # ── Task transitions ──────────────────────────────────────────

  defdelegate mark_task_running(task, child_run_id), to: Plans
  defdelegate mark_task_done(task), to: Plans
  defdelegate mark_task_failed(task, reason), to: Plans
end
