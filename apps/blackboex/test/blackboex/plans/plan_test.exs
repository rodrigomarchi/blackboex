defmodule Blackboex.Plans.PlanTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Plans.Plan

  setup do
    {user, org} = user_and_org_fixture()
    project = project_fixture(%{user: user, org: org})
    %{user: user, org: org, project: project}
  end

  defp valid_attrs(%{project: project}) do
    %{
      project_id: project.id,
      status: "draft",
      title: "Test Plan",
      user_message: "make a CRUD",
      markdown_body: "# Plan\n\n- step 1\n",
      model_tier_caps: %{}
    }
  end

  describe "valid_statuses/0" do
    test "returns expected list" do
      assert Plan.valid_statuses() == ~w(draft approved running done partial failed)
    end
  end

  describe "changeset/2" do
    test "valid with required fields", ctx do
      changeset = Plan.changeset(%Plan{}, valid_attrs(ctx))
      assert changeset.valid?
    end

    test "rejects unknown status", ctx do
      attrs = Map.put(valid_attrs(ctx), :status, "bogus")
      changeset = Plan.changeset(%Plan{}, attrs)
      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end

    test "missing required fields produces errors" do
      changeset = Plan.changeset(%Plan{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert Map.has_key?(errors, :project_id)
      assert Map.has_key?(errors, :title)
      assert Map.has_key?(errors, :user_message)
      assert Map.has_key?(errors, :markdown_body)
    end

    test "inserts successfully and persists fields", ctx do
      attrs = valid_attrs(ctx)

      assert {:ok, plan} =
               %Plan{}
               |> Plan.changeset(attrs)
               |> Repo.insert()

      assert plan.title == "Test Plan"
      assert plan.status == "draft"
    end
  end

  describe "UNIQUE-partial: one active plan per project" do
    test "rejects a second :approved plan for the same project", ctx do
      attrs = valid_attrs(ctx)

      assert {:ok, _first} =
               %Plan{}
               |> Plan.changeset(Map.put(attrs, :status, "approved"))
               |> Repo.insert()

      assert {:error, changeset} =
               %Plan{}
               |> Plan.changeset(Map.put(attrs, :status, "approved"))
               |> Repo.insert()

      refute changeset.valid?
      assert %{project_id: [_]} = errors_on(changeset)
    end

    test "rejects a :running plan when an :approved one already exists", ctx do
      attrs = valid_attrs(ctx)

      assert {:ok, _approved} =
               %Plan{}
               |> Plan.changeset(Map.put(attrs, :status, "approved"))
               |> Repo.insert()

      assert {:error, changeset} =
               %Plan{}
               |> Plan.changeset(Map.put(attrs, :status, "running"))
               |> Repo.insert()

      refute changeset.valid?
      assert %{project_id: [_]} = errors_on(changeset)
    end

    test "allows multiple :draft plans for the same project", ctx do
      attrs = valid_attrs(ctx)

      assert {:ok, _} = %Plan{} |> Plan.changeset(attrs) |> Repo.insert()
      assert {:ok, _} = %Plan{} |> Plan.changeset(attrs) |> Repo.insert()
    end

    test "allows :done and :partial plans alongside an active plan", ctx do
      attrs = valid_attrs(ctx)

      assert {:ok, _} =
               %Plan{} |> Plan.changeset(Map.put(attrs, :status, "done")) |> Repo.insert()

      assert {:ok, _} =
               %Plan{} |> Plan.changeset(Map.put(attrs, :status, "partial")) |> Repo.insert()

      assert {:ok, _} =
               %Plan{} |> Plan.changeset(Map.put(attrs, :status, "approved")) |> Repo.insert()
    end
  end

  describe "fixture sanity" do
    test "plan_fixture inserts a row", ctx do
      plan = plan_fixture(%{project: ctx.project})
      assert plan.id
      assert plan.status == "draft"
    end

    test "approved_plan_fixture creates an approved plan with one task", ctx do
      plan = approved_plan_fixture(%{project: ctx.project})
      assert plan.status == "approved"
      assert plan.approved_at
    end

    test "partial_plan_fixture creates a partial plan with done + failed tasks", ctx do
      plan = partial_plan_fixture(%{project: ctx.project})
      assert plan.status == "partial"
    end
  end
end
