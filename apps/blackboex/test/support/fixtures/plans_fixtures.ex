defmodule Blackboex.PlansFixtures do
  @moduledoc """
  Test helpers for creating `Plan` and `PlanTask` entities. Uses `Repo`
  directly so fixtures do not couple to the (M2) `Plans` facade.
  """

  alias Blackboex.Plans.Plan
  alias Blackboex.Plans.PlanTask
  alias Blackboex.Repo

  @doc """
  Creates a `Plan` for the given (or auto-created) project.

  Options:
    * `:project` — the Project (auto-created if absent)
    * `:user`, `:org` — forwarded to project auto-creation
    * `:status` — default `"draft"`
    * `:title`, `:user_message`, `:markdown_body`, `:run_id`,
      `:parent_plan_id`, `:approved_by_user_id`, `:approved_at`,
      `:failure_reason`, `:model_tier_caps` — passed through.
  """
  @spec plan_fixture(map()) :: Plan.t()
  def plan_fixture(attrs \\ %{}) do
    project =
      attrs[:project] ||
        Blackboex.ProjectsFixtures.project_fixture(Map.take(attrs, [:user, :org]))

    known_keys = [:project, :user, :org]
    extra = Map.drop(attrs, known_keys)

    base = %{
      project_id: project.id,
      status: "draft",
      title: "Test Plan",
      user_message: "build a CRUD for blog posts",
      markdown_body: "# Test Plan\n\n- [ ] Step 1\n",
      model_tier_caps: %{}
    }

    {:ok, plan} =
      %Plan{}
      |> Plan.changeset(Map.merge(base, extra))
      |> Repo.insert()

    plan
  end

  @doc """
  Creates a `PlanTask` for the given (or auto-created) plan.

  Auto-assigns `:order` to the next available position if not provided.
  """
  @spec plan_task_fixture(map()) :: PlanTask.t()
  def plan_task_fixture(attrs \\ %{}) do
    plan = attrs[:plan] || plan_fixture(Map.take(attrs, [:project, :user, :org]))

    known_keys = [:plan, :project, :user, :org]
    extra = Map.drop(attrs, known_keys)

    order = Map.get(extra, :order, next_order(plan.id))

    base = %{
      plan_id: plan.id,
      order: order,
      artifact_type: "api",
      action: "create",
      title: "Create posts API",
      params: %{},
      acceptance_criteria: [],
      status: "pending"
    }

    final_attrs =
      base
      |> Map.merge(Map.drop(extra, [:order]))
      |> Map.put(:order, order)

    {:ok, task} =
      %PlanTask{}
      |> PlanTask.changeset(final_attrs)
      |> Repo.insert()

    task
  end

  @doc """
  Builds a Plan in `:approved` state with one approved task. Useful for
  asserting concurrency invariants.
  """
  @spec approved_plan_fixture(map()) :: Plan.t()
  def approved_plan_fixture(attrs \\ %{}) do
    extra = Map.drop(attrs, [:project, :user, :org])

    plan =
      plan_fixture(
        Map.merge(
          attrs,
          Map.merge(extra, %{
            status: "approved",
            approved_at: DateTime.utc_now()
          })
        )
      )

    _task = plan_task_fixture(%{plan: plan})
    plan
  end

  @doc """
  Builds a Plan in `:partial` state with one `:done` and one `:failed`
  task — the canonical "needs continuation" shape.
  """
  @spec partial_plan_fixture(map()) :: Plan.t()
  def partial_plan_fixture(attrs \\ %{}) do
    extra = Map.drop(attrs, [:project, :user, :org])

    plan =
      plan_fixture(
        Map.merge(
          attrs,
          Map.merge(extra, %{status: "partial", failure_reason: "task 2 failed"})
        )
      )

    _done = plan_task_fixture(%{plan: plan, status: "done", order: 0})
    _failed = plan_task_fixture(%{plan: plan, status: "failed", order: 1, error_message: "boom"})
    plan
  end

  @doc """
  Named setup: creates a `Plan` for an existing user + org + project.

      setup [:register_and_log_in_user, :create_project, :create_plan]
  """
  @spec create_plan(map()) :: map()
  def create_plan(%{project: _project} = ctx) do
    %{plan: plan_fixture(Map.take(ctx, [:project, :user, :org]))}
  end

  @doc """
  Named setup: creates a `Plan` and one `PlanTask`.
  """
  @spec create_plan_task(map()) :: map()
  def create_plan_task(%{plan: plan} = _ctx) do
    %{plan_task: plan_task_fixture(%{plan: plan})}
  end

  def create_plan_task(%{project: _project} = ctx) do
    plan = plan_fixture(Map.take(ctx, [:project, :user, :org]))
    %{plan: plan, plan_task: plan_task_fixture(%{plan: plan})}
  end

  @doc """
  Named setup: creates a partial `Plan` (one `:done`, one `:failed` task).
  """
  @spec create_partial_plan(map()) :: map()
  def create_partial_plan(%{project: _project} = ctx) do
    %{partial_plan: partial_plan_fixture(Map.take(ctx, [:project, :user, :org]))}
  end

  defp next_order(plan_id) do
    import Ecto.Query, only: [from: 2]

    max =
      Repo.one(from t in PlanTask, where: t.plan_id == ^plan_id, select: max(t.order)) || -1

    max + 1
  end
end
