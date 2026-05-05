defmodule Blackboex.Plans.PlanTaskTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Plans.PlanTask

  setup do
    {user, org} = user_and_org_fixture()
    project = project_fixture(%{user: user, org: org})
    plan = plan_fixture(%{project: project})
    %{user: user, org: org, project: project, plan: plan}
  end

  defp valid_attrs(%{plan: plan}) do
    %{
      plan_id: plan.id,
      order: 0,
      artifact_type: "api",
      action: "create",
      title: "Create posts API",
      params: %{},
      acceptance_criteria: ["GET /posts returns 200"],
      status: "pending"
    }
  end

  describe "valid_*/0" do
    test "valid_artifact_types" do
      assert PlanTask.valid_artifact_types() == ~w(api flow page playground)
    end

    test "valid_actions" do
      assert PlanTask.valid_actions() == ~w(create edit)
    end

    test "valid_statuses includes :skipped" do
      assert PlanTask.valid_statuses() == ~w(pending running done failed skipped)
    end
  end

  describe "changeset/2" do
    test "valid with required fields", ctx do
      changeset = PlanTask.changeset(%PlanTask{}, valid_attrs(ctx))
      assert changeset.valid?
    end

    test "rejects invalid artifact_type", ctx do
      attrs = Map.put(valid_attrs(ctx), :artifact_type, "bogus")
      changeset = PlanTask.changeset(%PlanTask{}, attrs)
      refute changeset.valid?
      assert %{artifact_type: [_]} = errors_on(changeset)
    end

    test "rejects invalid action", ctx do
      attrs = Map.put(valid_attrs(ctx), :action, "bogus")
      changeset = PlanTask.changeset(%PlanTask{}, attrs)
      refute changeset.valid?
      assert %{action: [_]} = errors_on(changeset)
    end

    test "rejects invalid status", ctx do
      attrs = Map.put(valid_attrs(ctx), :status, "bogus")
      changeset = PlanTask.changeset(%PlanTask{}, attrs)
      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end

    test "rejects negative order", ctx do
      attrs = Map.put(valid_attrs(ctx), :order, -1)
      changeset = PlanTask.changeset(%PlanTask{}, attrs)
      refute changeset.valid?
      assert %{order: [_]} = errors_on(changeset)
    end

    test "missing required fields produces errors" do
      changeset = PlanTask.changeset(%PlanTask{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert Map.has_key?(errors, :plan_id)
      assert Map.has_key?(errors, :order)
      assert Map.has_key?(errors, :artifact_type)
      assert Map.has_key?(errors, :action)
      assert Map.has_key?(errors, :title)
    end

    test "unique (plan_id, order)", ctx do
      attrs = valid_attrs(ctx)

      assert {:ok, _first} =
               %PlanTask{}
               |> PlanTask.changeset(attrs)
               |> Repo.insert()

      assert {:error, changeset} =
               %PlanTask{}
               |> PlanTask.changeset(attrs)
               |> Repo.insert()

      refute changeset.valid?
      assert %{plan_id: [_]} = Map.take(errors_on(changeset), [:plan_id])
    end
  end

  describe ":skipped invariant — creation-time-only" do
    test "allows :skipped at insert time", ctx do
      attrs = Map.put(valid_attrs(ctx), :status, "skipped")

      assert {:ok, task} =
               %PlanTask{}
               |> PlanTask.changeset(attrs)
               |> Repo.insert()

      assert task.status == "skipped"
    end

    test "rejects updating an existing task to :skipped", ctx do
      task = plan_task_fixture(%{plan: ctx.plan})
      assert task.status == "pending"

      changeset = PlanTask.changeset(task, %{status: "skipped"})
      refute changeset.valid?
      assert %{status: [reason]} = errors_on(changeset)
      assert reason =~ "creation-time-only"
    end

    test "allows updating to other valid statuses", ctx do
      task = plan_task_fixture(%{plan: ctx.plan})

      changeset = PlanTask.changeset(task, %{status: "running"})
      assert changeset.valid?

      changeset = PlanTask.changeset(task, %{status: "done"})
      assert changeset.valid?

      changeset = PlanTask.changeset(task, %{status: "failed"})
      assert changeset.valid?
    end
  end

  describe "fixture sanity" do
    test "plan_task_fixture inserts a row", ctx do
      task = plan_task_fixture(%{plan: ctx.plan})
      assert task.id
      assert task.status == "pending"
    end

    test "plan_task_fixture auto-increments order", ctx do
      first = plan_task_fixture(%{plan: ctx.plan})
      second = plan_task_fixture(%{plan: ctx.plan})
      assert second.order == first.order + 1
    end
  end
end
