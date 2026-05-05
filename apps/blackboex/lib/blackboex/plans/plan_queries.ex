defmodule Blackboex.Plans.PlanQueries do
  @moduledoc """
  Composable query builders for `Plan` and `PlanTask`. Pure query
  construction — no `Repo.*` calls and no side effects.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Plans.Plan
  alias Blackboex.Plans.PlanTask

  @active_statuses ~w(approved running)

  @spec for_project(Ecto.UUID.t(), keyword()) :: Ecto.Query.t()
  def for_project(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    base =
      from(p in Plan,
        where: p.project_id == ^project_id,
        order_by: [desc: p.inserted_at],
        limit: ^limit
      )

    case Keyword.get(opts, :status) do
      nil -> base
      status when is_binary(status) -> from(p in base, where: p.status == ^status)
      statuses when is_list(statuses) -> from(p in base, where: p.status in ^statuses)
    end
  end

  @spec active_for_project(Ecto.UUID.t()) :: Ecto.Query.t()
  def active_for_project(project_id) do
    from(p in Plan,
      where: p.project_id == ^project_id and p.status in ^@active_statuses,
      limit: 1
    )
  end

  @spec tasks_for_plan(Ecto.UUID.t()) :: Ecto.Query.t()
  def tasks_for_plan(plan_id) do
    from(t in PlanTask,
      where: t.plan_id == ^plan_id,
      order_by: [asc: t.order]
    )
  end

  @spec done_tasks_for_plan(Ecto.UUID.t()) :: Ecto.Query.t()
  def done_tasks_for_plan(plan_id) do
    from(t in PlanTask,
      where: t.plan_id == ^plan_id and t.status == "done",
      order_by: [asc: t.order]
    )
  end

  @spec task_by_child_run_id(Ecto.UUID.t()) :: Ecto.Query.t()
  def task_by_child_run_id(child_run_id) do
    from(t in PlanTask, where: t.child_run_id == ^child_run_id, limit: 1)
  end

  @spec running_tasks_with_child_run_id() :: Ecto.Query.t()
  def running_tasks_with_child_run_id do
    from(t in PlanTask,
      where: t.status == "running" and not is_nil(t.child_run_id),
      preload: [:plan]
    )
  end
end
